pub fn print_host_header(host: &str) {
    println!();
    println!("{host}");
}

pub fn print_table(headers: &[&str], rows: &[Vec<String>]) {
    let mut widths = headers.iter().map(|header| header.len()).collect::<Vec<_>>();

    for row in rows {
        for (index, field) in row.iter().enumerate() {
            widths[index] = widths[index].max(field.len());
        }
    }

    print_row(headers, &widths);
    print_separator(&widths);
    for row in rows {
        print_row_strings(row, &widths);
    }
}

fn print_row(fields: &[&str], widths: &[usize]) {
    for (index, field) in fields.iter().enumerate() {
        if index > 0 {
            print!("  ");
        }
        print!("{field:<width$}", width = widths[index]);
    }
    println!();
}

fn print_row_strings(fields: &[String], widths: &[usize]) {
    for (index, field) in fields.iter().enumerate() {
        if index > 0 {
            print!("  ");
        }
        print!("{field:<width$}", width = widths[index]);
    }
    println!();
}

fn print_separator(widths: &[usize]) {
    for (index, width) in widths.iter().enumerate() {
        if index > 0 {
            print!("  ");
        }
        print!("{}", "-".repeat(*width));
    }
    println!();
}

