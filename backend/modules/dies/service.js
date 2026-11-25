'use strict';

const {
  DIE_TYPE_SLUGS,
  buildDieCode,
  nextFreeDieCode,
  isUsableDieType,
} = require('./die-identity');

// ---------------------------------------------------------------------------
// The die master: reading it, shaping it for the wire, and the one upsert.
//
// Takes {get, all, run, parseJson} plus two link functions. A die's client is
// not a column but a single die↔client link in entity_links, owned by the links
// module, which mounts late. So the link functions come in as callers rather
// than values:
//
//   resolveLinks(entityType, ids, targetType) -> Map(id -> {id, ...})
//   writeLink(entityType, id, targetType, targetId | null)
//
// Orders' production report and trace also shape dies for the wire, so
// rowToDieDto is exported for them rather than copied.
//
// saveDie does not know about HTTP. It either returns what it saved, or a
// `refusal` ({status, body}) for the cases the caller must answer with
// something other than a 500.
// ---------------------------------------------------------------------------

function createDieService({ get, all, run, parseJson, resolveLinks, writeLink, desk }) {
  /// Free text in a JSON column, read as the one value it plainly is.
  ///
  /// `produced_part_numbers` is declared as JSON, but real rows in a live
  /// workspace hold things like `Penta faceplate pierce` — typed in before the
  /// column meant anything stricter. A bare JSON.parse threw on the first such
  /// row and, because the whole list is mapped in one pass, took the entire
  /// `/api/dies` response down with it: the Dies screen showed nothing at all,
  /// and the error said only "Unexpected token 'P'".
  ///
  /// One unparseable row must cost that row's structure, not everybody's data.
  function dieJsonList(value) {
    const parsed = parseJson(value, null);
    if (Array.isArray(parsed)) return parsed;
    if (parsed && typeof parsed === 'object') return [parsed];
    const text = String(value ?? '').trim();
    return text ? [text] : [];
  }

  function rowToDieDto(r) {
    return {
      id: String(r.id),
      toolCode: r.tool_code,
      producedPartNumbers: dieJsonList(r.produced_part_numbers),
      photoUrls: dieJsonList(r.photo_urls),
      operationalNotes: r.operational_notes,
      compatibleMachineGroupIds: dieJsonList(r.compatible_machine_group_ids),
      storageLocation: r.storage_location,
      // The die sheet (migrations/048). Null stays null: never measured and
      // measured at zero are different answers, which is why these are not
      // `|| 0`.
      dieType: r.die_type || '',
      // The words for a type the shop typed. Empty for the built-in four, whose
      // label is looked up from the slug on either side.
      dieTypeLabel: r.die_type_label || '',
      // `madeBy` survives beside `dieMakerId` rather than being replaced by it:
      // every die that existed before the master has a name and no id, and that
      // is a legal state. A reader prefers the id and falls back to the text.
      madeBy: r.made_by || '',
      dieMakerId: r.die_maker_id == null ? null : Number(r.die_maker_id),
      poAt: r.po_at || null,
      dateInAt: r.date_in_at || null,
      linerSizeNm: r.liner_size_nm == null ? null : Number(r.liner_size_nm),
      linerSizeUnit: r.liner_size_unit || 'mm',
      noOfSet: r.no_of_set == null ? null : Number(r.no_of_set),
      storeArea: r.store_area || '',
      rackNo: r.rack_no || '',
      numberOfCavities: r.number_of_cavities,
      strokeCount: r.stroke_count,
      maxStrokes: r.max_strokes,
      strokesPerPiece: r.strokes_per_piece,
      setupMinutes: r.setup_minutes,
      reportNotes: r.report_notes || '',
      physicalSpecs: parseJson(r.physical_specs, {}) ?? {},
      status: r.status,
      ownership: r.ownership,
      createdAt: new Date(r.created_at).toISOString(),
      updatedAt: new Date(r.updated_at).toISOString(),
    };
  }

  /// Dies with the client each belongs to, resolved in one pass for the list.
  ///
  /// The die form's Client picker was sent on every save and stored nowhere —
  /// dies have no client column — so the choice vanished on reload. It lives in
  /// entity_links as a single die↔client link and is read back here.
  async function diesWithClients(rows) {
    const present = rows.filter(Boolean);
    const clients = present.length
      ? await resolveLinks('die', present.map((row) => String(row.id)), 'client')
      : new Map();
    return present.map((row) => {
      const link = clients.get(String(row.id));
      return { ...rowToDieDto(row), clientId: link ? Number(link.id) : null };
    });
  }

  /// A die's row as stored, or undefined.
  const getDieRow = (id) => get('SELECT * FROM dies WHERE id = ?', [id]);

  /// Every die as stored, for a report that keys them by id and tool code.
  const allDieRows = () => all('SELECT * FROM dies');

  /// The die a pipeline node names: nodes carry a tool code.
  const getDieRowByToolCode = (toolCode) => get('SELECT * FROM dies WHERE tool_code = ?', [toolCode]);

  /// Deletes the row and nothing else: an approved delete request.
  const removeDieRow = (id) => run('DELETE FROM dies WHERE id = ?', [id]);

  async function listDies() {
    const rows = await all('SELECT * FROM dies ORDER BY created_at DESC');
    return diesWithClients(rows);
  }

  /// One die as the wire shows it, or null.
  async function getDie(id) {
    const r = await get('SELECT * FROM dies WHERE id = ?', [id]);
    if (!r) return null;
    const [die] = await diesWithClients([r]);
    return die;
  }

  async function saveDie(body) {
    const {
      id,
      toolCode,
      producedPartNumbers,
      photoUrls,
      operationalNotes,
      compatibleMachineGroupIds,
      storageLocation,
      numberOfCavities,
      strokeCount,
      maxStrokes,
      strokesPerPiece,
      setupMinutes,
      reportNotes,
      physicalSpecs,
      status,
      ownership,
      // The die sheet (migrations/048).
      dieType,
      dieTypeLabel,
      madeBy,
      dieMakerId,
      poAt,
      dateInAt,
      linerSizeNm,
      linerSizeUnit,
      noOfSet,
      storeArea,
      rackNo,
      // Accepted for DERIVATION ONLY and never stored: which part a die makes
      // is item_dies, not a column here.
      partCode,
      // Which client the die belongs to. There is no column: it is a single
      // die↔client link (entity_links), as a set's group is. Absent keeps it.
      clientId,
    } = body || {};

    if (clientId !== undefined && clientId !== null && clientId !== '') {
      const { exists } = await desk.ask('clients.exists', { id: clientId });
      if (!exists) {
        return { refusal: { status: 400, body: { success: false, die: null, error: 'That client does not exist.' } } };
      }
    }

    const now = new Date().toISOString();
    // The id arrives as a number from the app (B69) and as a string from
    // older callers and the Dies / Machines screens; both must update.
    const idText = id === undefined || id === null ? '' : String(id).trim();
    const isUpdate = idText !== '' && !idText.startsWith('temp_') && Number.isFinite(Number(idText));
    const beforeRow = isUpdate
      ? await get('SELECT * FROM dies WHERE id = ?', [Number(id)])
      : null;
    if (isUpdate && !beforeRow) {
      return { refusal: { status: 404, body: { success: false, die: null, error: 'Die not found.' } } };
    }

    // Every field preserves what is stored when the caller does not mention
    // it. This route is an upsert that used to write every column from the
    // body, so the first save from the Dies screen after the wizard filled in
    // a maker would have blanked it — the photo_url bug, one table over, and
    // already live for the columns that were here before.
    const kept = (value, column, fallback = null) =>
      value !== undefined ? value : (beforeRow ? beforeRow[column] : fallback);
    const keptText = (value, column) => {
      const chosen = kept(value, column, '');
      return chosen === null || chosen === undefined ? '' : String(chosen);
    };
    const keptJson = (value, column, empty) =>
      value !== undefined ? JSON.stringify(value ?? empty) : (beforeRow?.[column] ?? JSON.stringify(empty));
    const keptInt = (value, column) => {
      const chosen = kept(value, column);
      return chosen === null || chosen === undefined || chosen === '' ? null : Number(chosen);
    };

    const normalizedDieType = String(keptText(dieType, 'die_type')).trim();
    // A built-in type is named by its slug, so a custom label kept from
    // before the type was switched would only sit there stale.
    const normalizedDieTypeLabel = DIE_TYPE_SLUGS.includes(normalizedDieType)
      ? ''
      : String(keptText(dieTypeLabel, 'die_type_label')).trim();

    // A typed type is allowed, but only with its label.
    //
    // This used to refuse any slug outside the built-in four. It now refuses a
    // slug it cannot recover a LABEL for, which is the thing that actually
    // matters: the code is built from the label's initials, so an unknown slug
    // with no label beside it would store a die whose code can never be
    // re-derived — and `buildDieCode` would quietly return '' rather than
    // anything wrong-looking.
    if (!isUsableDieType(normalizedDieType, normalizedDieTypeLabel)) {
      return {
        refusal: {
          status: 400,
          body: {
            success: false,
            die: null,
            error: `"${normalizedDieType}" is not a die type, and no name was given for it.`,
          },
        },
      };
    }

    // A maker that is not there would fail the foreign key and come back as a
    // 500; an archived one would be linked silently. Only a NEWLY sent id is
    // checked — a die keeps the maker it already has even once archived.
    const resolvedDieMakerId = keptInt(dieMakerId, 'die_maker_id');
    if (
      dieMakerId !== undefined &&
      resolvedDieMakerId !== null &&
      resolvedDieMakerId !== (beforeRow ? beforeRow.die_maker_id : null)
    ) {
      const maker = await get('SELECT id, is_archived FROM die_makers WHERE id = ?', [
        resolvedDieMakerId,
      ]);
      if (!maker || maker.is_archived) {
        return {
          refusal: {
            status: 400,
            body: {
              success: false,
              die: null,
              code: 'die_maker_unknown',
              error: maker
                ? 'That die maker is archived. Unarchive it first, or pick another.'
                : 'That die maker does not exist.',
            },
          },
        };
      }
    }

    // Derived before the timestamp fallback, so a die made against a part is
    // named after it rather than after the clock. The fallback stays for a die
    // created from nothing, which the Dies screen can still do.
    let finalToolCode = String(toolCode || '').trim();
    if (!finalToolCode && !isUpdate) {
      finalToolCode = buildDieCode({
        dieType: normalizedDieType,
        dieTypeLabel: normalizedDieTypeLabel,
        partCode,
      });
    }
    if (!finalToolCode) {
      finalToolCode = isUpdate ? String(beforeRow.tool_code) : `DIE-${Date.now()}`;
    }

    // Named before the index refuses it, so the message can say who holds the
    // code and the client can offer a free one. tool_code is unique across the
    // whole factory while a part code is unique only within its group, so this
    // is expected traffic rather than an edge case.
    const clash = await get(
      'SELECT id, tool_code FROM dies WHERE UPPER(tool_code) = ? AND (? IS NULL OR id <> ?)',
      [finalToolCode.toUpperCase(), isUpdate ? Number(id) : null, isUpdate ? Number(id) : null],
    );
    if (clash) {
      const free = await nextFreeDieCode(finalToolCode, {
        get,
        excludeId: isUpdate ? Number(id) : null,
      });
      return {
        refusal: {
          status: 409,
          body: {
            success: false,
            die: null,
            code: 'die_tool_code_duplicate',
            suggestedToolCode: free || null,
            error: free
              ? `Die code "${finalToolCode}" is already used by die #${clash.id}. Try "${free}".`
              : `Die code "${finalToolCode}" is already used by die #${clash.id}.`,
          },
        },
      };
    }

    const columns = [
      finalToolCode,
      keptJson(producedPartNumbers, 'produced_part_numbers', []),
      keptJson(photoUrls, 'photo_urls', []),
      kept(operationalNotes, 'operational_notes'),
      keptJson(compatibleMachineGroupIds, 'compatible_machine_group_ids', []),
      kept(storageLocation, 'storage_location'),
      keptInt(numberOfCavities, 'number_of_cavities'),
      Number(kept(strokeCount, 'stroke_count', 0) || 0),
      Number(kept(maxStrokes, 'max_strokes', 0) || 0),
      keptInt(strokesPerPiece, 'strokes_per_piece'),
      keptInt(setupMinutes, 'setup_minutes'),
      keptText(reportNotes, 'report_notes'),
      keptJson(physicalSpecs, 'physical_specs', {}),
      kept(status, 'status'),
      kept(ownership, 'ownership'),
      normalizedDieType,
      normalizedDieTypeLabel,
      keptText(madeBy, 'made_by').trim(),
      resolvedDieMakerId,
      kept(poAt, 'po_at'),
      kept(dateInAt, 'date_in_at'),
      keptInt(linerSizeNm, 'liner_size_nm'),
      keptText(linerSizeUnit, 'liner_size_unit') || 'mm',
      keptInt(noOfSet, 'no_of_set'),
      keptText(storeArea, 'store_area').trim(),
      keptText(rackNo, 'rack_no').trim(),
    ];

    let resultId = id;
    try {
      if (isUpdate) {
        await run(
          `UPDATE dies SET tool_code = ?, produced_part_numbers = ?, photo_urls = ?, operational_notes = ?, compatible_machine_group_ids = ?, storage_location = ?, number_of_cavities = ?, stroke_count = ?, max_strokes = ?, strokes_per_piece = ?, setup_minutes = ?, report_notes = ?, physical_specs = ?, status = ?, ownership = ?, die_type = ?, die_type_label = ?, made_by = ?, die_maker_id = ?, po_at = ?, date_in_at = ?, liner_size_nm = ?, liner_size_unit = ?, no_of_set = ?, store_area = ?, rack_no = ?, updated_at = ? WHERE id = ?`,
          [...columns, now, Number(id)],
        );
      } else {
        const info = await run(
          `INSERT INTO dies (tool_code, produced_part_numbers, photo_urls, operational_notes, compatible_machine_group_ids, storage_location, number_of_cavities, stroke_count, max_strokes, strokes_per_piece, setup_minutes, report_notes, physical_specs, status, ownership, die_type, die_type_label, made_by, die_maker_id, po_at, date_in_at, liner_size_nm, liner_size_unit, no_of_set, store_area, rack_no, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [...columns, now, now],
        );
        resultId = String(info.lastID);
      }
    } catch (error) {
      // The index is the real guard and catches the race the check above
      // cannot. Same answer, so it reads the same to the client.
      if (String(error.message || '').includes('UNIQUE constraint failed: dies.tool_code')) {
        return {
          refusal: {
            status: 409,
            body: {
              success: false,
              die: null,
              code: 'die_tool_code_duplicate',
              error: `Die code "${finalToolCode}" was taken a moment ago. Pick another.`,
            },
          },
        };
      }
      throw error;
    }

    if (clientId !== undefined) {
      await writeLink(
        'die',
        String(resultId),
        'client',
        clientId === null || clientId === '' ? null : String(clientId),
      );
    }
    const row = await get('SELECT * FROM dies WHERE id = ?', [resultId]);
    const [die] = await diesWithClients([row]);
    return { isUpdate, resultId, beforeRow, row, die };
  }

  /// The row about to go, and its removal. Whether it MAY go is the caller's
  /// question (a live run holds it), and so are the links and variations that
  /// hang off it.
  async function deleteDie(id) {
    const before = await get('SELECT * FROM dies WHERE id = ?', [id]);
    await run('DELETE FROM dies WHERE id = ?', [id]);
    return before;
  }

  return { rowToDieDto, getDieRow, getDieRowByToolCode, allDieRows, removeDieRow, listDies, getDie, saveDie, deleteDie };
}

module.exports = { createDieService };
