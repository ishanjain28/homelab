pub fn parse_size(value: &str) -> Result<u64, String> {
    let value = value.trim();
    let split_at = value
        .find(|character: char| !character.is_ascii_digit())
        .unwrap_or(value.len());
    let number = value[..split_at]
        .parse::<u64>()
        .map_err(|error| format!("invalid size {value:?}: {error}"))?;
    let suffix = value[split_at..]
        .trim()
        .trim_end_matches('B')
        .to_ascii_uppercase();
    let multiplier = match suffix.as_str() {
        "" => 1,
        "K" | "KI" => 1024,
        "M" | "MI" => 1024_u64.pow(2),
        "G" | "GI" => 1024_u64.pow(3),
        "T" | "TI" => 1024_u64.pow(4),
        "P" | "PI" => 1024_u64.pow(5),
        unsupported => {
            return Err(format!(
                "unsupported size suffix {unsupported:?} in {value:?}"
            ))
        }
    };

    number
        .checked_mul(multiplier)
        .ok_or_else(|| format!("size is too large: {value:?}"))
}
