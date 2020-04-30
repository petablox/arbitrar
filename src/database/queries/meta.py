import pprint

pp = pprint.PrettyPrinter(indent=2)


def print_counts(data) -> str:
  max_len = 0
  for key, _ in data:
    max_len = max(max_len, len(key))
  for key, count in data:
    space = ' ' * (max_len - len(key))
    print(f'{key}:{space} {count}')


class QueryExecutor:
  def setup_parser(parser):
    pass

  def execute(args):
    pass
