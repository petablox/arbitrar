from ..meta import Executor


class PackagesQuery(Executor):
  @staticmethod
  def execute(args):
    db = args.db
    print("Name\t\tFetch Status\tBuild Status")
    for package in db.packages:
      f = "fetched" if package.fetched else "not fetched"
      b = package.build.result.value
      print(f"{package.name}\t\t{f}\t\t{b}")
