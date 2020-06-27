# Adapted from
# https://github.com/nicococo/tilitools/blob/master/tilitools/utils_kernel.py

import numpy as np

def get_kernel(X, Y, type='rbf', param=2.0, verbose=0):
    """Calculates a kernel given the data X and Y (dims x exms)"""
    _, Xn = X.shape
    _, Yn = Y.shape

    kernel = 1.0
    if type == 'linear':
        # print('Calculating linear kernel with size {0}x{1}.'.format(Xn, Yn))
        kernel = X.T.dot(Y)

    if type == 'rbf':
        # print('Calculating Gaussian kernel with size {0}x{1} and sigma2={2}.'.format(Xn, Yn, param))
        Dx = (np.ones((Yn, 1)) * np.diag(X.T.dot(X)).reshape(1, Xn)).T
        Dy = (np.ones((Xn, 1)) * np.diag(Y.T.dot(Y)).reshape(1, Yn))
        kernel = Dx - 2. * np.array(X.T.dot(Y)) + Dy
        kernel = np.exp(-kernel / param)
    return kernel
