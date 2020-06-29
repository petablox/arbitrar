from . import unsupervised, supervised, active

learners = {'unsupervised': unsupervised, 'supervised': supervised, 'active': active}


def setup_parser(parser):
  subparsers = parser.add_subparsers(dest='learner')
  for key, executor in learners.items():
    query_parser = subparsers.add_parser(key)
    executor.setup_parser(query_parser)


def main(args):
  if args.learner in learners:
    learners[args.learner].main(args)
  else:
    print(f"Unknown query {args.learner}")
