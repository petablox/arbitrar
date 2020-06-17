import sys

from src.database.helpers import SourceFeatureVisualizer

class ActiveLearner:
  def __init__(self, datapoints, xs, amount, args):
    self.datapoints = datapoints
    self.xs = xs
    self.amount = amount
    self.args = args

  def run(self):
    ps = list(enumerate(self.xs))
    outlier_count = 0
    auc_graph = []

    if self.args.source:
      vis = SourceFeatureVisualizer(self.args.source)

    try:
      for attempt_count in range(self.amount):
        p_i = self.select(ps)
        if p_i == None:
          break

        dp_i = self.datapoints[p_i]
        item = (p_i, self.xs[p_i])

        if self.args.ground_truth:
          is_alarm = dp_i.has_label(label=self.args.ground_truth)
          print(f"Attemp {attempt_count} is alarm: {str(is_alarm)}    ", end="\r")
        elif self.args.source:
          # If the ground truth is not provided
          # Ask the user to label. y: Is Outlier, n: Not Outlier, u: Unknown
          result = vis.ask(dp_i,
                           ["y", "n"],
                           prompt=f"Attempt {attempt_count}: Do you think this is a bug? [y|n] > ",
                           scroll_down_key="]",
                           scroll_up_key="[")
          if result != "q":
            if result == "y":
              is_alarm = True
            elif result == "n":
              is_alarm = False
          else:
            break
        else:
          print("Must provide --ground-truth or --source. Aborting")
          sys.exit()

        if is_alarm:
          outlier_count += 1

        self.feedback(item, is_alarm)

        ps = [(i, x) for (i, x) in ps if i != p_i]
        auc_graph.append(outlier_count)

    except SystemExit:
      print("Aborting")
      sys.exit()
    except Exception as err:
      if self.args.source:
        vis.destroy()
      raise err

    # Remove the visualizer
    if self.args.source:
      vis.destroy()
    else:
      print("")

    # return the result alarms and auc_graph
    return self.alarms(ps), auc_graph

  def select(self, ps):
    raise Exception("Child class of Active Learner should override this function")

  def feedback(self, item, is_alarm):
    pass

  def alarms(self, ps):
    raise Exception("Child class of Active Learner should override this function")
