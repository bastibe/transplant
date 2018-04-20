from transplant import Matlab, TransplantError
import numpy as np
import pytest
import warnings

test_data = np.array([[1, 2, 3],
                      [4, 5, 6]])

@pytest.yield_fixture
def matlab(request):
    matlab = Matlab(jvm=False)
    yield matlab
    del matlab

def test_put_and_get(matlab):
    matlab.test_data = test_data
    assert np.all(matlab.test_data == test_data)

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
    matlab.test_data = impossible_to_write
    transferred_back = matlab.test_data
    def all_indices():
        for a in range(5):
            for b in range(4):
                for c in range(3):
                    for d in range(2):
                        yield (a, b, c, d)
    for a, b, c, d in all_indices():
        p = impossible_to_write[a, b, c, d]
        evalstr = 'test_data({},{},{},{})'.format(a+1, b+1, c+1, d+1)
        m = matlab.evalin('base', evalstr, nargout=1)
        b = transferred_back[a, b, c, d]
        assert p == m == b

def test_sparse_matrices(matlab):
    # construct a sparse matrix with ten random numbers at random places:
    import scipy.sparse
    matrix = np.zeros([10, 10])
    random_x = np.random.randint(10, size=10)
    random_y = np.random.randint(10, size=10)
    matrix[random_x, random_y] = np.random.randn(10)
    # convert to sparse and transfer to matlab:
    sparse = scipy.sparse.csc_matrix(matrix)
    matlab.test = sparse

    for x, y in zip(range(matrix.shape[0]), range(matrix.shape[1])):
        m = matlab.evalin('base', 'test({}, {})'.format(x+1, y+1), nargout=1)
        with warnings.catch_warnings():
            warnings.filterwarnings('ignore', category=scipy.sparse.SparseEfficiencyWarning)
            assert matrix[x, y] == sparse[x, y] == m

def test_empty_sparse_matrices(matlab):
    import scipy.sparse
    matrix = np.zeros([2, 2])
    # send an empty sparse matrix to matlab
    assert matlab.issparse(scipy.sparse.csc_matrix(matrix))
    # get an empty sparse matrix from matlab
    assert isinstance(matlab.sparse(2.0, 2.0), scipy.sparse.spmatrix)

def test_big_matrices(matlab):
    matrix = np.zeros([1, 256])
    x = matlab.sum(matrix)
    assert x == 0

    import scipy.sparse
    x = matlab.sum(scipy.sparse.csc_matrix(matrix))
    assert x == 0

def test_function_passing(matlab):
    x = matlab.feval(matlab.plus, 1., 2.)
    assert x == 3.

def test_docstring(matlab):
    docstring = matlab.ones.__doc__
    assert 'ONES' in docstring
    classdocstring = type(matlab.ones).__doc__
    assert 'ONES' in classdocstring
