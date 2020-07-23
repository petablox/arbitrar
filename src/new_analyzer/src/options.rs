use clap::{App, ArgMatches};

pub trait Options: Sized {
  fn setup_parser<'a>(app: App<'a>) -> App<'a>;

  fn from_matches(matches: &ArgMatches) -> Result<Self, String>;
}
