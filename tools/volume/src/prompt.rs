use std::fs::File;
use std::io::{Read, Write};

pub fn confirm(prompt: &str) -> Result<bool, String> {
    let reply = prompt_tty(&format!("{prompt} [yes/no] "))?;
    Ok(reply == "yes")
}

fn prompt_tty(prompt: &str) -> Result<String, String> {
    let mut tty = File::options()
        .read(true)
        .write(true)
        .open("/dev/tty")
        .map_err(|error| format!("failed to open /dev/tty: {error}"))?;
    tty.write_all(prompt.as_bytes())
        .and_then(|_| tty.flush())
        .map_err(|error| format!("failed to write prompt: {error}"))?;

    let mut reply = String::new();
    let mut byte = [0_u8; 1];
    while tty
        .read(&mut byte)
        .map_err(|error| format!("failed to read prompt reply: {error}"))?
        == 1
    {
        if byte[0] == b'\n' {
            break;
        }
        reply.push(byte[0] as char);
    }
    Ok(reply.trim().to_string())
}
