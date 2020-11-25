import sys
import copy

from src.database.helpers import SourceFeatureVisualizer, AnimatedScatter
from src.database import FunctionSpec

import numpy as np
from sklearn.manifold import TSNE
import matplotlib.pyplot as plt


def x_to_string(x):
  return "".join([str(x_i) for x_i in x.tolist()])


class ActiveLearner:
  def __init__(self, datapoints, xs, amount, args, log_newline=False, output_anim=False):
    self.datapoints = datapoints
    self.xs = xs
    self.amount = amount
    self.args = args
    self.log_newline = log_newline
    self.output_anim = output_anim
    # if self.args.ground_truth:
    #   if self.args.num_outliers != None:
    #     self.num_outliers = self.args.num_outliers
    #   else:
    #     print("Loading ground truth labels...")
    #     self.num_outliers = len([0 for dp in self.datapoints if dp.has_label(label=self.args.ground_truth)])
    self.explored_cache = {}

    # TSNE
    if output_anim:
      tsne_fitter = TSNE(n_components=2, verbose=2, n_iter=500)
      self.xs_fitted = tsne_fitter.fit_transform(self.xs)
      self.xs_fitted_colors = ['b' for _ in self.xs]

  def mark(self, bc, slice_id, trace_id, is_bug):
    for (j, dp) in enumerate(self.datapoints):
      if dp.bc == bc and dp.slice_id == slice_id:
        if trace_id == None or dp.trace_id == trace_id:
          print("Marking ", bc, slice_id, trace_id, " as ", "bug" if is_bug else "non-bug")
          self.feedback((j, self.xs[j]), is_bug)

  def run(self):
    log_end = "\n" if self.log_newline else "\r"
    ps = list(enumerate(self.xs))
    outlier_count = 0
    auc_graph = [0]
    alarms_perc_graph = []
    pospoints = []

    animation_frames = []
    tsne_fig, tsne_ax = plt.subplots()

    if self.args.ground_truth:
      pass
    elif self.args.function_spec:
      spec = FunctionSpec(self.args.function_spec)
    else:
      is_interactive = True
      vis = SourceFeatureVisualizer()

    try:
      for attempt_count in range(self.amount):
        p_i = self.select(ps)
        if p_i == None:
          break

        dp_i = self.datapoints[p_i]
        item = (p_i, self.xs[p_i])

        if self.args.ground_truth:
          is_alarm = dp_i.has_label(label=self.args.ground_truth)
          mark_whole_slice = False
          print(f"Attempt {attempt_count} is alarm: {str(is_alarm)}" + (" " * 30), end=log_end)

        elif self.args.function_spec:
          is_alarm = not spec.match(dp_i)
          mark_whole_slice = False
          print(f"Attempt {attempt_count} is alarm: {str(is_alarm)}" + (" " * 30), end=log_end)

        else:
          # If the ground truth is not provided
          # Ask the user to label. y: Is Outlier, n: Not Outlier, u: Unknown
          result = vis.ask(dp_i, ["y", "Y", "n", "N"],
                           prompt=f"Attempt {attempt_count}: Do you think this is a bug? [y|Y|n|N] > ",
                           scroll_down_key="]",
                           scroll_up_key="[",
                           padding=self.args.padding)

          # Get the user label
          if result != "q":

            # Check is alarm
            if result == "y" or result == "Y":
              is_alarm = True
            elif result == "n" or result == "N":
              is_alarm = False

            # Check if we need to mark the whole slice
            if result == "Y" or result == "N":
              mark_whole_slice = True
            else:
              mark_whole_slice = False

          else:
            break

        # Mark whole slice
        if mark_whole_slice:
          for j in range(max(p_i - 50, 0), min(p_i + 50, len(self.datapoints))):
            dp_j = self.datapoints[j]
            if dp_j.slice_id == dp_i.slice_id:
              self.feedback((j, self.xs[j]), is_alarm)
              ps = [(i, x) for (i, x) in ps if i != j]

              if is_alarm:
                pospoints.append((dp_j, attempt_count))
                if self.output_anim:
                  self.xs_fitted_colors[j] = 'r'
              else:
                if self.output_anim:
                  self.xs_fitted_colors[j] = 'g'

              # Simulate the process
              if not is_interactive:
                if is_alarm:
                  outlier_count += 1
                auc_graph.append(outlier_count)

          if is_interactive:
            if is_alarm:
              outlier_count += 1
            auc_graph.append(outlier_count)

        else:
          self.feedback(item, is_alarm)
          ps = [(i, x) for (i, x) in ps if i != p_i]

          # Simulate the process
          if is_alarm:
            pospoints.append((dp_i, attempt_count))
            outlier_count += 1
            if self.output_anim:
              self.xs_fitted_colors[p_i] = 'r'
          else:
            if self.output_anim:
              self.xs_fitted_colors[p_i] = 'g'
          auc_graph.append(outlier_count)

        if self.output_anim:
          animation_frames.append(copy.deepcopy(self.xs_fitted_colors))

        # tsne_ax.scatter(self.xs_fitted[:, 0], self.xs_fitted[:, 1], c=self.xs_fitted_colors, s=2)

        # Alarms Percentage Graph
        # if self.args.ground_truth:
        #   alarms = self.alarms(self.num_outliers)
        #   if len(alarms) > 0:
        #     true_alarms = [(dp, score) for (dp, score) in alarms if dp.has_label(label=self.args.ground_truth)]
        #     alarms_perc_graph.append(len(true_alarms) / len(alarms))
        #   else:
        #     alarms_perc_graph.append(0)

    except SystemExit:
      print("Aborting")
      sys.exit()
    except KeyboardInterrupt:
      print("Stopping...")
    except Exception as err:
      if self.args.source:
        vis.destroy()
      raise err

    # Remove the visualizer
    if self.args.source:
      vis.destroy()
    else:
      print("")

    if self.output_anim:
      tsne_animation = AnimatedScatter(self.xs_fitted, animation_frames)
    else:
      tsne_animation = None

    # return the result alarms and auc_graph
    return self.alarms(self.args.num_alarms), auc_graph, alarms_perc_graph, pospoints, tsne_animation

  def select(self, ps):
    raise Exception("Child class of Active Learner should override this function")

  def feedback(self, item, is_alarm):
    pass

  def alarms(self, num_alarms):
    raise Exception("Child class of Active Learner should override this function")
