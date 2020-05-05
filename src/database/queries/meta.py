import pprint

pp = pprint.PrettyPrinter(indent=2)


def print_counts(data):
  max_len = 0
  for key, _ in data:
    max_len = max(max_len, len(key))
  for key, count in data:
    space = ' ' * (max_len - len(key))
    print(f'{key}:{space} {count}')


class QueryExecutor:
  @staticmethod
  def setup_parser(parser):
    pass

  @staticmethod
  def execute(args):
    pass
