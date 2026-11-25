'use strict';

const {
  buildMachineNo,
  nextMachineNo,
  nextFreeMachineNo,
} = require('./machine-identity');

// ---------------------------------------------------------------------------
// The machine master: reading it, shaping it for the wire, and the one upsert.
//
// Takes {get, all, run, parseJson}. Orders' production report and trace also
// shape machines for the wire, so rowToMachineDto is exported for them rather
// than copied; they hand it a row they have already read.
//
// saveMachine does not know about HTTP. It either returns what it saved, or a
// `refusal` ({status, body}) for the cases the caller has to answer with
// something other than a 500: a machine that is not there, a capacity kind that
// is not one, a machine number somebody already holds.
// ---------------------------------------------------------------------------

function createMachineService({ get, all, run, parseJson, desk }) {
  function rowToMachineDto(r) {
    return {
      id: String(r.id),
      name: r.name,
      assetId: r.asset_id,
      barcode: r.barcode && r.barcode.length ? r.barcode : r.asset_id,
      primaryPhotoUrl: r.primary_photo_url,
      groupId: r.group_id,
      // The machine sheet (migrations/049). Null stays null: never read and
      // read as zero are different answers.
      machineMake: r.machine_make || '',
      manufacturedYear: r.manufactured_year == null ? null : Number(r.manufactured_year),
      // The date of manufacture, when it was picked as one ('YYYY-MM-DD').
      manufacturedOn: r.manufactured_on || null,
      feederMake: r.feeder_make || '',
      runningHours: r.running_hours == null ? null : Number(r.running_hours),
      strokesPerMinute:
        r.strokes_per_minute == null ? null : Number(r.strokes_per_minute),
      capacityKind: r.capacity_kind || '',
      capacityKgf: r.capacity_kgf == null ? null : Number(r.capacity_kgf),
      dieFeedType: r.die_feed_type || '',
      makeModel: r.make_model,
      serialNumber: r.serial_number,
      location: r.location,
      installationDate: r.installation_date ? new Date(r.installation_date).toISOString() : null,
      status: r.status,
      reportOutputPerHour: r.report_output_per_hour,
      setupMinutes: r.setup_minutes,
      laborCount: r.labor_count,
      powerKw: r.power_kw,
      reportNotes: r.report_notes || '',
      customProperties: JSON.parse(r.custom_properties || '[]'),
      capabilities: parseJson(r.capabilities_json, []),
      createdAt: new Date(r.created_at).toISOString(),
      updatedAt: new Date(r.updated_at).toISOString(),
    };
  }

  /// The row as stored, or undefined.
  const getMachineRow = (id) => get('SELECT * FROM machines WHERE id = ?', [id]);

  /// Every machine as stored, for a report that keys them by id, number and name.
  const allMachineRows = () => all('SELECT * FROM machines');

  /// The machine a pipeline node names: nodes carry a machine number or a name.
  const getMachineRowByAssetOrName = (key) =>
    get('SELECT * FROM machines WHERE asset_id = ? OR name = ?', [key, key]);

  /// Deletes the row and nothing else: an approved delete request.
  const removeMachineRow = (id) => run('DELETE FROM machines WHERE id = ?', [id]);

  async function listMachines() {
    const rows = await all('SELECT * FROM machines ORDER BY created_at DESC');
    return rows.map(rowToMachineDto);
  }

  /// One machine as the wire shows it, or null.
  async function getMachine(id) {
    const r = await get('SELECT * FROM machines WHERE id = ?', [id]);
    return r ? rowToMachineDto(r) : null;
  }

  async function saveMachine(body) {
    const {
      id,
      name,
      assetId,
      barcode,
      primaryPhotoUrl,
      groupId,
      makeModel,
      serialNumber,
      location,
      installationDate,
      status,
      reportOutputPerHour,
      setupMinutes,
      laborCount,
      powerKw,
      reportNotes,
      customProperties,
      // What the machine can do (migrations/059). Absent keeps them.
      capabilities,
      // The machine sheet (migrations/049).
      machineMake,
      manufacturedYear,
      manufacturedOn,
      feederMake,
      runningHours,
      strokesPerMinute,
      capacityKind,
      capacityKgf,
      dieFeedType,
    } = body || {};

    const now = new Date().toISOString();
    // The id arrives as a number from the app (B69) and as a string from
    // older callers and the Dies / Machines screens; both must update.
    const idText = id === undefined || id === null ? '' : String(id).trim();
    const isUpdate = idText !== '' && !idText.startsWith('temp_') && Number.isFinite(Number(idText));
    const beforeRow = isUpdate
      ? await get('SELECT * FROM machines WHERE id = ?', [Number(id)])
      : null;
    if (isUpdate && !beforeRow) {
      return { refusal: { status: 404, body: { success: false, machine: null, error: 'Machine not found.' } } };
    }

    // Every field preserves what is stored when the caller does not mention
    // it. This route is an upsert that used to write every column from the
    // body, so the first save from the Machines screen after the wizard filled
    // in a maker would have blanked it — the same bug /api/dies had, and
    // already live here for the columns that were here before.
    const kept = (value, column, fallback = null) =>
      value !== undefined ? value : (beforeRow ? beforeRow[column] : fallback);
    const keptText = (value, column) => {
      const chosen = kept(value, column, '');
      return chosen === null || chosen === undefined ? '' : String(chosen);
    };
    const keptInt = (value, column) => {
      const chosen = kept(value, column);
      return chosen === null || chosen === undefined || chosen === '' ? null : Number(chosen);
    };

    const normalizedCapacityKind = String(keptText(capacityKind, 'capacity_kind')).trim();
    if (normalizedCapacityKind && !['rated', 'free_hand'].includes(normalizedCapacityKind)) {
      return {
        refusal: {
          status: 400,
          body: {
            success: false,
            machine: null,
            error: `"${normalizedCapacityKind}" is not a capacity kind.`,
          },
        },
      };
    }
    const normalizedGroupId = kept(groupId, 'group_id');

    // Derived from the machine's type before the timestamp fallback, so a
    // press is named after what it is rather than after the clock. The
    // fallback stays for a machine created with no type.
    let finalAssetId = String(assetId || '').trim();
    if (!finalAssetId && !isUpdate && normalizedGroupId) {
      const group = await desk.ask('items.groups.name', { id: Number(normalizedGroupId) });
      finalAssetId = buildMachineNo({
        groupName: group?.name || '',
        nextNumber: await nextMachineNo({ groupId: normalizedGroupId }, { get }),
      });
    }
    if (!finalAssetId) {
      finalAssetId = isUpdate ? String(beforeRow.asset_id) : `MACH-${Date.now()}`;
    }

    // Named before the index refuses it, so the message can say which machine
    // holds the number and the client can offer a free one. asset_id is unique
    // across the whole plant while the series is per type, so a clash is
    // expected traffic rather than an edge case.
    const clash = await get(
      'SELECT id, asset_id FROM machines WHERE UPPER(asset_id) = ? AND (? IS NULL OR id <> ?)',
      [finalAssetId.toUpperCase(), isUpdate ? Number(id) : null, isUpdate ? Number(id) : null],
    );
    if (clash) {
      const free = await nextFreeMachineNo(finalAssetId, {
        get,
        excludeId: isUpdate ? Number(id) : null,
      });
      return {
        refusal: {
          status: 409,
          body: {
            success: false,
            machine: null,
            code: 'machine_asset_id_duplicate',
            suggestedAssetId: free || null,
            error: free
              ? `Machine No "${finalAssetId}" is already used by machine #${clash.id}. Try "${free}".`
              : `Machine No "${finalAssetId}" is already used by machine #${clash.id}.`,
          },
        },
      };
    }

    // Machine barcode defaults to the asset tag when the client doesn't supply one.
    const keptBarcode = keptText(barcode, 'barcode').trim();
    const finalBarcode = keptBarcode !== '' ? keptBarcode : finalAssetId;

    const columns = [
      keptText(name, 'name'),
      finalAssetId,
      finalBarcode,
      kept(primaryPhotoUrl, 'primary_photo_url'),
      normalizedGroupId,
      kept(makeModel, 'make_model'),
      kept(serialNumber, 'serial_number'),
      kept(location, 'location'),
      kept(installationDate, 'installation_date'),
      kept(status, 'status'),
      keptInt(reportOutputPerHour, 'report_output_per_hour'),
      keptInt(setupMinutes, 'setup_minutes'),
      keptInt(laborCount, 'labor_count'),
      keptInt(powerKw, 'power_kw'),
      keptText(reportNotes, 'report_notes'),
      customProperties !== undefined
        ? JSON.stringify(customProperties || [])
        : (beforeRow?.custom_properties ?? '[]'),
      keptText(machineMake, 'machine_make').trim(),
      keptInt(manufacturedYear, 'manufactured_year'),
      keptText(feederMake, 'feeder_make').trim(),
      keptInt(runningHours, 'running_hours'),
      keptInt(strokesPerMinute, 'strokes_per_minute'),
      normalizedCapacityKind,
      // Only a rated machine carries a figure: free hand means there is none,
      // and keeping the old number beside that kind would be two answers.
      normalizedCapacityKind === 'rated' ? keptInt(capacityKgf, 'capacity_kgf') : null,
      keptText(dieFeedType, 'die_feed_type').trim(),
      capabilities !== undefined
        ? JSON.stringify(Array.isArray(capabilities) ? capabilities : [])
        : (beforeRow?.capabilities_json ?? '[]'),
    ];

    let resultId = id;
    try {
      if (isUpdate) {
        await run(
          `UPDATE machines SET name = ?, asset_id = ?, barcode = ?, primary_photo_url = ?, group_id = ?, make_model = ?, serial_number = ?, location = ?, installation_date = ?, status = ?, report_output_per_hour = ?, setup_minutes = ?, labor_count = ?, power_kw = ?, report_notes = ?, custom_properties = ?, machine_make = ?, manufactured_year = ?, feeder_make = ?, running_hours = ?, strokes_per_minute = ?, capacity_kind = ?, capacity_kgf = ?, die_feed_type = ?, capabilities_json = ?, updated_at = ? WHERE id = ?`,
          [...columns, now, Number(id)],
        );
      } else {
        const info = await run(
          `INSERT INTO machines (name, asset_id, barcode, primary_photo_url, group_id, make_model, serial_number, location, installation_date, status, report_output_per_hour, setup_minutes, labor_count, power_kw, report_notes, custom_properties, machine_make, manufactured_year, feeder_make, running_hours, strokes_per_minute, capacity_kind, capacity_kgf, die_feed_type, capabilities_json, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [...columns, now, now],
        );
        resultId = String(info.lastID);
      }
    } catch (error) {
      // The index is the real guard and catches the race the check above
      // cannot. Same answer, so it reads the same to the client.
      if (String(error.message || '').includes('UNIQUE constraint failed: machines.asset_id')) {
        return {
          refusal: {
            status: 409,
            body: {
              success: false,
              machine: null,
              code: 'machine_asset_id_duplicate',
              error: `Machine No "${finalAssetId}" was taken a moment ago. Pick another.`,
            },
          },
        };
      }
      throw error;
    }

    // D.O.M. as a date: absent keeps it, null or '' clears it, a date sets
    // it and its year with it.
    if (manufacturedOn !== undefined) {
      const text = manufacturedOn == null ? '' : String(manufacturedOn).trim();
      const day = text.slice(0, 10);
      if (text && !/^\d{4}-\d{2}-\d{2}$/.test(day)) {
        return {
          refusal: {
            status: 400,
            body: { success: false, machine: null, error: 'D.O.M. must be a date (YYYY-MM-DD).' },
          },
        };
      }
      await run(
        day
          ? 'UPDATE machines SET manufactured_on = ?, manufactured_year = ? WHERE id = ?'
          : 'UPDATE machines SET manufactured_on = NULL WHERE id = ?',
        day ? [day, Number(day.slice(0, 4)), Number(resultId)] : [Number(resultId)],
      );
    }

    const row = await get('SELECT * FROM machines WHERE id = ?', [resultId]);
    return { isUpdate, resultId, beforeRow, row, machine: rowToMachineDto(row) };
  }

  /// The row about to go, and its removal. Whether it MAY go is the caller's
  /// question (a live run holds it), and so are the links and variations that
  /// hang off it.
  async function deleteMachine(id) {
    const before = await get('SELECT * FROM machines WHERE id = ?', [id]);
    await run('DELETE FROM machines WHERE id = ?', [id]);
    return before;
  }

  return { rowToMachineDto, getMachineRow, getMachineRowByAssetOrName, allMachineRows, removeMachineRow, listMachines, getMachine, saveMachine, deleteMachine };
}

module.exports = { createMachineService };
