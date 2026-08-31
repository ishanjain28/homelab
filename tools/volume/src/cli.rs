use crate::apply::run_apply;
use crate::check::run_check;
use crate::delete::run_delete;
use crate::migrate::run_migrate;
use crate::models::Context;
use clap::{Parser, Subcommand};
use std::env;
use std::path::PathBuf;

#[derive(Parser)]
#[command(name = "volume")]
#[command(about = "Homelab volume management helper")]
struct Cli {
    #[command(subcommand)]
    command: VolumeCommand,
}

#[derive(Subcommand)]
enum VolumeCommand {
    /// SSH into each host and verify declared homelab volumes.
    Check {
        /// Hosts to check. Defaults to all nixosConfigurations.
        hosts: Vec<String>,
    },

    /// SSH into each host and apply volume disk changes step by step.
    Apply {
        /// Hosts to apply. Defaults to all nixosConfigurations.
        hosts: Vec<String>,
    },

    /// Delete declared volumes from one host after verifying they have no user data.
    Delete {
        /// Host containing the volume.
        host: String,

        /// Declared volume IDs to delete.
        volume_ids: Vec<String>,
    },

    /// Compare configured volume locations against actual LVM volumes by UUID.
    Migrate {
        /// Hosts to inspect. Defaults to all nixosConfigurations.
        hosts: Vec<String>,
    },
}

pub fn run() -> Result<(), String> {
    let cli = Cli::parse();
    let context = Context {
        flake: env::var("HOMELAB_FLAKE").unwrap_or_else(|_| ".".to_string()),
        ssh_config: ssh_config(),
    };

    match cli.command {
        VolumeCommand::Check { hosts } => run_check(&context, &hosts),
        VolumeCommand::Apply { hosts } => run_apply(&context, &hosts),
        VolumeCommand::Delete { host, volume_ids } => run_delete(&context, &host, &volume_ids),
        VolumeCommand::Migrate { hosts } => run_migrate(&context, &hosts),
    }
}

fn ssh_config() -> String {
    let path = env::var("HOME")
        .map(PathBuf::from)
        .map(|home| home.join(".ssh/config"))
        .unwrap_or_else(|_| PathBuf::from("/dev/null"));

    if path.is_file() {
        path.to_string_lossy().into_owned()
    } else {
        "/dev/null".to_string()
    }
}

