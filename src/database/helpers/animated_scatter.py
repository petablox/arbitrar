import numpy as np
import matplotlib.pyplot as plt

from matplotlib import animation, rc

# Please do the following:
#   conda install -c conda-forge ffmpeg


class AnimatedScatter(object):
  def __init__(self, positions, colors):
    self.positions = positions
    self.colors = colors
    self.stream = self.data_stream()
    self.fig, self.ax = plt.subplots()
    self.anim = animation.FuncAnimation(self.fig,
                                        self.update,
                                        frames=len(colors),
                                        interval=20,
                                        init_func=self.setup_plot,
                                        blit=False)

  def setup_plot(self):
    self.scat = self.ax.scatter(self.positions[:, 0], self.positions[:, 1], s=3, vmin=0, vmax=1, edgecolor="k")
    # self.ax.axis([0, 50, 0, 50])
    return self.scat,

  def data_stream(self):
    frame = 0
    while True:
      yield self.colors[frame]
      frame += 1

  def update(self, i):
    color = next(self.stream)
    self.scat.set_color(color)
    return self.scat,
