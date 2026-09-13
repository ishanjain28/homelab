mod apply;
mod backup;
mod cli;
mod lock;
mod models;
mod operation;
mod prompt;
mod restic;
mod restore;
mod retire;
mod snapshot;
mod table;
mod util;

fn main() {
    env_logger::init();

    if let Err(error) = cli::run() {
        log::error!("{error}");
        std::process::exit(1);
    }
}
