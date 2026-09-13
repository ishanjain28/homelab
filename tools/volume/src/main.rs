mod apply;
mod cli;
mod lock;
mod lvm;
mod models;
mod retire;
mod transfer;
mod util;

fn main() {
    env_logger::init();

    if let Err(error) = cli::run() {
        log::error!("{error}");
        std::process::exit(1);
    }
}
