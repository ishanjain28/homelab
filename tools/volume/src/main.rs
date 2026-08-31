mod apply;
mod check;
mod cli;
mod delete;
mod migrate;
mod models;
mod nix;
mod prompt;
mod remote;
mod table;
mod util;

fn main() {
    if let Err(error) = cli::run() {
        eprintln!("{error}");
        std::process::exit(1);
    }
}

