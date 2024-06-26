{ lib
, buildPythonPackage
, django
, fetchPypi
, pythonOlder
}:

buildPythonPackage rec {
  pname = "django-webpack-loader";
  version = "3.0.1";
  format = "setuptools";

  disabled = pythonOlder "3.7";

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-UTMbM9p2aI60078+o7tWQ0sMHfstzYjL+wo5YY9o3Xo=";
  };

  propagatedBuildInputs = [
    django
  ];

  # django.core.exceptions.ImproperlyConfigured (path issue with DJANGO_SETTINGS_MODULE?)
  doCheck = false;

  pythonImportsCheck = [
    "webpack_loader"
  ];

  meta = with lib; {
    description = "Use webpack to generate your static bundles";
    homepage = "https://github.com/owais/django-webpack-loader";
    changelog = "https://github.com/django-webpack/django-webpack-loader/blob/${version}/CHANGELOG.md";
    license = with licenses; [ mit ];
    maintainers = with maintainers; [ peterromfeldhk ];
  };
}
