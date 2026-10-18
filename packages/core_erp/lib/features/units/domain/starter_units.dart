/// The units a workspace needs before it can hold anything.
///
/// A fresh install has exactly one unit — `Primary Unit`, symbol `-`, written
/// by the server's `ensurePrimaryGroupAndUnit` — and an item cannot be created
/// without a unit at all: the contract refuses it. So the first thing a new
/// workspace asks of someone is that they stop and invent kilograms.
///
/// **Names and symbols only.** [CreateUnitInput] takes a `conversionFactor`
/// and a `unitGroupName` and both are deliberately left alone: nothing in Paper
/// can yet convert between units — `unit_groups` is empty, every
/// `conversion_factor` is 1.0 and every `conversion_base_unit_id` is NULL
/// (`.claude/skills/units` §0). Seeding `1 kg = 1000 g` would be a claim the
/// system cannot honour, and a wrong number in the data is worse than no
/// number. These are seven ordinary units, editable and deletable like any
/// other.
///
/// The spellings are the ones the server's own demo seeder uses
/// (`ensureDemoUnitsPresent`), so a workspace that has seen demo data and one
/// that has not end up with the same rows rather than `Piece` beside `pcs`.
/// Millimetre is the one addition: sheet metal is specified in it everywhere
/// in this product.
library;

import 'unit_inputs.dart';

/// One unit to offer, as the server's demo seeder spells it.
class StarterUnit {
  const StarterUnit({
    required this.name,
    required this.symbol,
    required this.notes,
  });

  final String name;
  final String symbol;
  final String notes;

  CreateUnitInput toInput() =>
      CreateUnitInput(name: name, symbol: symbol, notes: notes);
}

const List<StarterUnit> kStarterUnits = <StarterUnit>[
  StarterUnit(
    name: 'Piece',
    symbol: 'Pc',
    notes: 'Discrete finished goods and components.',
  ),
  StarterUnit(name: 'Box', symbol: 'Box', notes: 'Packed kits and boxes.'),
  StarterUnit(name: 'Carton', symbol: 'Ctn', notes: 'Shipping cartons.'),
  StarterUnit(name: 'Meter', symbol: 'm', notes: 'Length measurement.'),
  StarterUnit(
    name: 'Millimeter',
    symbol: 'mm',
    notes: 'Sheet and strip dimensions.',
  ),
  StarterUnit(name: 'Liter', symbol: 'L', notes: 'Volume measurement.'),
  StarterUnit(name: 'Kilogram', symbol: 'kg', notes: 'Weight measurement.'),
  StarterUnit(name: 'Gram', symbol: 'g', notes: 'Small weight measurement.'),
];

String _fold(String value) => value.trim().toLowerCase();

/// Which starter units a workspace holding [existingNames] / [existingSymbols]
/// does not have yet.
///
/// Matched on name **or** symbol, so neither `Kilogram` nor a lone `kg` gets a
/// twin, and pressing the offer twice adds nothing the second time. Archived
/// units count as present: re-creating one would put two rows with the same
/// name in the master, one of them invisible.
List<StarterUnit> missingStarterUnits({
  required Iterable<String> existingNames,
  required Iterable<String> existingSymbols,
}) {
  final names = existingNames.map(_fold).toSet();
  final symbols = existingSymbols.map(_fold).toSet();
  return kStarterUnits
      .where(
        (unit) =>
            !names.contains(_fold(unit.name)) &&
            !symbols.contains(_fold(unit.symbol)),
      )
      .toList(growable: false);
}

/// Whether a workspace looks untouched: nothing but the server's placeholder.
///
/// `Primary Unit` is written by the server on first boot, so its presence is
/// not a sign that anyone has set anything up. Archived units are ignored here
/// for the same reason the offer is drawn anyway — this only decides whether to
/// bring the offer forward, never whether it is allowed.
bool unitsLookUnset({
  required Iterable<String> activeUnitNames,
  Iterable<String> placeholders = const <String>['primary unit'],
}) {
  final placeholderNames = placeholders.map(_fold).toSet();
  return activeUnitNames.every((name) => placeholderNames.contains(_fold(name)));
}
