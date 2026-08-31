pub fn non_empty_lines(output: &str) -> Vec<String> {
    output
        .lines()
        .filter(|line| !line.trim().is_empty())
        .map(ToOwned::to_owned)
        .collect()
}

pub fn parse_u64(value: &str, host: &str, id: &str, name: &str) -> Result<u64, String> {
    value
        .parse::<u64>()
        .map_err(|error| format!("[{host}/{id}] invalid {name} {value:?}: {error}"))
}

pub fn trim_octal(value: &str) -> String {
    let trimmed = value.trim_start_matches('0');
    if trimmed.is_empty() {
        "0".to_string()
    } else {
        trimmed.to_string()
    }
}

