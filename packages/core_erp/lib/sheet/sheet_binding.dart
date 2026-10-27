import 'column_option.dart';
import 'sheet_draft.dart';

/// What a sheet's pickers and checks read from.
///
/// Every one of these is already a `SheetController` constructor parameter —
/// the prototype simply passed literals. Gathering them behind one type means
/// the supplier is the binding (which holds the providers) rather than the
/// screen, so a second entity supplies its own without the screen learning
/// about it.
class SheetReferenceData {
  const SheetReferenceData({
    this.options = const [],
    this.parties = const [],
    this.contacts = const [],
    this.counters = const {},
    this.existingCodes = const {},
    this.existingPaths = const {},
  });

  final List<ColumnOption> options;
  final List<Party> parties;
  final List<Contact> contacts;

  /// Last used running number per group path — what a `seq` column counts on.
  final Map<String, int> counters;

  /// Codes already taken, so a second row cannot be typed into a collision the
  /// server would refuse.
  final Set<String> existingCodes;

  /// Group paths that already hold a part of that name.
  final Set<String> existingPaths;
}

/// How a sheet's rows become an entity, and back.
///
/// The engine deliberately knows nothing about items, dies or machines — it
/// imports exactly one domain helper (`partCodeInitials`) and should keep that
/// property. A binding is where entity knowledge lives, so a second entity is a
/// second binding rather than a second engine.
///
/// The counterpart to this is `ColumnDef.bindsTo`: without it a cell is keyed
/// by `columnId` alone and every binding degenerates into a table of literal
/// ids, which is what the prototype screen had — 34 sites using raw column
/// numbers.
/// **Extend this, do not implement it** — [referenceData] has a usable default
/// and `implements` would make every binding write an empty one by hand.
abstract class SheetBinding<T> {
  /// Writes the rows and answers the saved entities.
  ///
  /// Returns null when nothing was written. A binding must distinguish "the
  /// save failed" from "the save did not happen", because the provider layer
  /// underneath answers null for both: `ItemsProvider._save` returns null with
  /// no error set when a save is already in flight.
  Future<List<T>?> save(List<SheetDraft> rows);

  /// Writes ONE row and answers the entity, or null with [lastError] set.
  ///
  /// The unit a sheet commits in. [save] loops this, and loses nothing when a
  /// row in the middle fails: each row is its own write, so a refusal is that
  /// row's problem and the rows already committed stay committed.
  ///
  /// The batching version could not say that. It returned null on the first
  /// failure and **threw away the list of entities it had already created**,
  /// which left rows on the server that the sheet believed were unsaved — and
  /// a second attempt then collided with them.
  Future<T?> saveRow(SheetDraft row);

  /// Projects entities back into rows, for loading an existing record.
  List<SheetDraft> toDrafts(List<T> entities);

  /// Why the last [save] answered null, for the status bar. Null when the last
  /// save succeeded.
  String? get lastError;

  /// Adds a person at [partyId] and answers them, or null when it failed.
  ///
  /// A company has as many people as it has and a deal is done with whoever
  /// picked up the phone, so a sheet that can only PICK a contact can only
  /// record deals with people somebody already entered elsewhere. Default
  /// answers null — a binding with no party master has nobody to add one to.
  Future<Contact?> addContact(int partyId, String name) async => null;

  /// The people at [partyId] as rows of a people sheet, with [ticked] people
  /// marked as dealt with. Default is nobody — a binding with no party master
  /// has no people to show.
  List<SheetDraft> peopleRows(int partyId, {Set<int> ticked = const {}}) =>
      const [];

  /// Adds a company by name and answers it, or null with [lastError] set.
  /// Default answers null — a binding with no party master cannot add one.
  Future<Party?> addParty(String name) async => null;

  /// Whether [partyId]'s people are known — its record has loaded, so an
  /// empty [peopleRows] means "nobody on file" rather than "not loaded yet".
  bool knowsParty(int partyId) => false;

  /// Writes one people-sheet row at [partyId] — a new person, or a change to
  /// one already on file — and answers their id, or null with [lastError] set.
  Future<int?> savePerson(int partyId, SheetDraft row) async => null;

  /// Called once after a batch of [savePerson] writes, so the binding can
  /// refresh its masters once rather than per person.
  Future<void> peopleSaved() async {}

  /// The deal [entity] was saved with, as a deal-sheet row plus the people
  /// ticked on it — for opening a record. Null when the entity records no
  /// outside party, or the binding has no deal.
  ({SheetDraft deal, Set<int> ticked})? dealOf(T entity) => null;

  /// The record with [id] as this binding last knew it, or null. Default
  /// knows none — a binding that cannot look records up cannot load one into
  /// a row when its name is picked.
  T? entityById(int id) => null;

  /// The record with [id] as a sheet row, or null. Its own method rather than
  /// `toDrafts([entityById(id)])`: a list built here is a `List<Object?>`,
  /// which a typed binding's `toDrafts` refuses at run time.
  SheetDraft? draftForId(int id) => null;

  /// The options, parties and uniqueness sets this sheet's cells read from.
  ///
  /// Default is empty so a binding can be written for saving alone; a host that
  /// wants real pickers overrides it.
  Future<SheetReferenceData> referenceData() async =>
      const SheetReferenceData();
}

/// What a cell feeds. The strings `ColumnDef.bindsTo` holds.
///
/// Named rather than loose literals so a typo is a compile error on the
/// binding side and a missing case is findable.
abstract final class SheetBindsTo {
  // Item identity.
  static const group = 'group';
  static const set = 'set';
  static const name = 'name';
  static const partNo = 'partNo';
  static const partCode = 'partCode';

  /// `variation:<Property Name>` — a top-level variation property whose value
  /// is this cell. The suffix is the property's name, so the column's label and
  /// the property it feeds cannot drift apart.
  static const variationPrefix = 'variation:';
  static String variation(String property) => '$variationPrefix$property';
  static bool isVariation(String? binds) =>
      binds != null && binds.startsWith(variationPrefix);
  static String variationProperty(String binds) =>
      binds.substring(variationPrefix.length);

  // The development deal. Only these three are writable — the contact fields
  // are resolved server-side on read, so writing them is a no-op.
  static const developedForParty = 'developedFor.party';
  static const developedForQuotation = 'developedFor.quotationAmount';
  static const developedForCost = 'developedFor.costAmount';

  /// Read-only projections of the chosen party, shown but never written.
  static const developedForContact = 'developedFor.contact';
  static const developedForDesignation = 'developedFor.designation';
  static const developedForPhone = 'developedFor.phone';
  static const developedForEmail = 'developedFor.email';

  /// A person at the deal's company, one per row of the people sheet. These
  /// ARE written — to the company's record of that person — and the tick is
  /// written to the part, as the deal's `contactIds`.
  static const personDealtWith = 'person.dealtWith';
  static const personName = 'person.name';
  static const personDesignation = 'person.designation';
  static const personPhone = 'person.phone';
  static const personEmail = 'person.email';

  /// Server-set stamps.
  static const createdDate = 'stamp:createdDate';
  static const createdTime = 'stamp:createdTime';
}
