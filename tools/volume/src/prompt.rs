use dialoguer::Confirm;

pub fn confirm(prompt: &str) -> Result<bool, String> {
    Confirm::new()
        .with_prompt(prompt)
        .default(false)
        .interact()
        .map_err(|error| format!("failed to read confirmation: {error}"))
}
