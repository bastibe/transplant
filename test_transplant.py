from transplant import Matlab
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
    with pytest.raises(NameError):
        matlab.foo

def test_call(matlab):
    size = matlab.call('size', [test_data])
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

def test_data_type(matlab):
    matlab.eval('test = uint8([1 2 3; 4 5 6]);')
    assert matlab.get('test').dtype == 'uint8'
    matlab.test = np.array(test_data, dtype='int16')
    assert matlab.eval('class(test)') == 'int16'
