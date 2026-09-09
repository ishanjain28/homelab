mod apply;
mod cli;
mod models;
mod prompt;
mod snapshot;
mod table;
mod util;

fn main() {
    if let Err(error) = cli::run() {
        eprintln!("{error}");
        std::process::exit(1);
    }
}
