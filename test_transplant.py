from transplant import Matlab, TransplantError
import numpy as np
import pytest

test_data = np.array([[1, 2, 3],
                      [4, 5, 6]])

@pytest.yield_fixture
def matlab(request):
    matlab = Matlab(arguments=('-nodesktop', '-nosplash', '-nojvm'))
    yield matlab
    del matlab

def test_put_and_get(matlab):
    matlab.test = test_data
    assert np.all(matlab.test == test_data)

def test_invalid_get(matlab):
    with pytest.raises(TransplantError):
        matlab.foo

def test_call(matlab):
    size = matlab.size(test_data)
    assert np.all(size == test_data.shape)

def test_interactive_call(matlab):
    size = matlab.size(test_data)
    assert np.all(size == test_data.shape)

def test_nargout_auto(matlab):
    max = matlab.max(test_data, nargout=0)
    assert np.all(max == np.max(test_data, axis=0))

def test_nargout_one(matlab):
    max = matlab.max(test_data, nargout=1)
    assert np.all(max == np.max(test_data, axis=0))

def test_nargout_two(matlab):
    max, idx = matlab.max(test_data, nargout=2)
    assert np.all(max == np.max(test_data, axis=0))
    assert np.all(idx-1 == np.argmax(test_data, axis=0))

def test_matrices(matlab):
    # construct a four-dimensional array that is (kind of) easy to reason about
    # first two dimensions (2x3):
    easy_to_write = np.array([[1, 2],
                              [3, 4],
                              [5, 6]])
    # third dimension (2x3x4):
    hard_to_write = np.array([easy_to_write,
                              easy_to_write*10,
                              easy_to_write*100,
                              easy_to_write*1000])
    # fourth dimension (2x3x4x5):
    impossible_to_write = np.array([(1+0j)*hard_to_write,
                                    (1+1j)*hard_to_write,
                                    (0+1j)*hard_to_write,
                                    (-1+1j)*hard_to_write,
                                    (-1+0j)*hard_to_write])
    # transfer to matlab:
    matlab.test = impossible_to_write
    transferred_back = matlab.test
    def all_indices():
        for a in range(5):
            for b in range(4):
                for c in range(3):
                    for d in range(2):
                        yield (a, b, c, d)
    for a, b, c, d in all_indices():
        p = impossible_to_write[a, b, c, d]
        evalstr = 'test({},{},{},{})'.format(a+1, b+1, c+1, d+1)
        m = matlab.evalin('base', evalstr, nargout=1)
        b = transferred_back[a, b, c, d]
        assert p == m == b
