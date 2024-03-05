{ lib
, buildPythonPackage
, pythonOlder
, fetchFromGitHub
, pytest-xdist
, pytestCheckHook
, setuptools-scm
, fastprogress
, jax
, jaxlib
, jaxopt
, optax
, typing-extensions
}:

buildPythonPackage rec {
  pname = "blackjax";
  version = "1.1.1";
  pyproject = true;

  disabled = pythonOlder "3.9";

  src = fetchFromGitHub {
    owner = "blackjax-devs";
    repo = "blackjax";
    rev = "refs/tags/${version}";
    hash = "sha256-6+ElY1F8oRCtWT4a/LIG6hYMthlq5mDx2baKAc6zIns=";
  };

  nativeBuildInputs = [ setuptools-scm ];

  propagatedBuildInputs = [
    fastprogress
    jax
    jaxlib
    jaxopt
    optax
    typing-extensions
  ];

  nativeCheckInputs = [
    pytestCheckHook
    pytest-xdist
  ];
  disabledTestPaths = [ "tests/test_benchmarks.py" ];
  disabledTests = [
    # too slow
    "test_adaptive_tempered_smc"
  ];

  pythonImportsCheck = [
    "blackjax"
  ];

  meta = with lib; {
    homepage = "https://blackjax-devs.github.io/blackjax";
    description = "Sampling library designed for ease of use, speed and modularity";
    changelog = "https://github.com/blackjax-devs/blackjax/releases/tag/${version}";
    license = licenses.asl20;
    maintainers = with maintainers; [ bcdarwin ];
  };
}
