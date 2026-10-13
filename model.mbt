///|
pub(all) enum FatigueError {
  InvalidInput(String)
  NumericOverflow(String)
} derive(Debug, Eq, ToJson)

///|
/// Stress range and mean in MPa; count is 1 or 0.5 for extracted cycles.
/// Indices refer to the original samples, including any plateaus.
pub(all) struct Cycle {
  range_mpa : Double
  mean_mpa : Double
  count : Double
  start_index : Int
  end_index : Int
} derive(ToJson)

///|
pub(all) struct SpectrumBin {
  lower_range_mpa : Double
  upper_range_mpa : Double
  count : Double
} derive(ToJson)

///|
/// S-N point: stress amplitude, NOT stress range. Points ascend in amplitude
/// and strictly descend in allowable cycles; no endurance-limit extrapolation.
pub(all) struct SNPoint {
  amplitude_mpa : Double
  cycles_to_failure : Double
} derive(ToJson, FromJson)

///|
pub(all) struct CycleDamage {
  cycle_index : Int
  amplitude_mpa : Double
  mean_mpa : Double
  count : Double
  allowable_cycles : Double?
  damage : Double?
} derive(ToJson)

///|
/// total_damage is absent if any nonzero-amplitude cycle is out of range.
/// evaluated_damage is only the sum of the supported subset in that case.
pub(all) struct DamageResult {
  total_damage : Double?
  evaluated_damage : Double
  out_of_range_cycles : Array[Int]
  mean_stress_model : String
  contributions : Array[CycleDamage]
} derive(ToJson)

///|
pub extend FatigueError with @debug.Debug::{to_repr}

///|
pub extend FatigueError with Eq::{equal, not_equal}

///|
pub extend FatigueError with ToJson::{to_json}

///|
pub extend Cycle with ToJson::{to_json}

///|
pub extend SpectrumBin with ToJson::{to_json}

///|
pub extend SNPoint with ToJson::{to_json}

///|
pub extend SNPoint with @json.FromJson::{from_json}

///|
pub extend CycleDamage with ToJson::{to_json}

///|
pub extend DamageResult with ToJson::{to_json}
