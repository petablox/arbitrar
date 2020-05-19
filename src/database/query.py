from . import utils
from .queries import *

query_executors = {
    'packages': PackagesQuery,
    'bc-files': BCFilesQuery,
    'occurrence': OccurrenceQuery,
    'num-slices': NumSlicesQuery,
    'slice': SliceQuery,
    'slices': SlicesQuery,
    'num-traces': NumTracesQuery,
    'dugraph': DUGraphQuery,
    'feature': FeatureQuery,
    'features': FeaturesQuery,
    'labels': LabelsQuery,
    'alarms': AlarmsQuery
}


def setup_parser(parser):
  subparsers = parser.add_subparsers(dest="query")
  for key, executor in query_executors.items():
    query_parser = subparsers.add_parser(key)
    executor.setup_parser(query_parser)


def main(args):
  if args.query in query_executors:
    query_executors[args.query].execute(args)
  else:
    print(f"Unknown query {args.query}")
