{ lib
, python3Packages
, fetchPypi
, ffmpeg
}:

python3Packages.buildPythonApplication rec {
  pname = "streamlink";
  version = "6.6.2";
  format = "pyproject";

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-0UF8fFmG3BQ7xxHIqZ97iEsQ0lg/RLHD2t6n3wp15NU=";
  };

  nativeCheckInputs = with python3Packages; [
    pytestCheckHook
    mock
    requests-mock
    freezegun
    pytest-asyncio
    pytest-trio
  ];

  propagatedBuildInputs = (with python3Packages; [
    certifi
    isodate
    lxml
    pycountry
    pycryptodome
    pysocks
    requests
    trio
    trio-websocket
    typing-extensions
    urllib3
    websocket-client
  ]) ++ [
    ffmpeg
  ];

  meta = with lib; {
    changelog = "https://github.com/streamlink/streamlink/raw/${version}/CHANGELOG.md";
    description = "CLI for extracting streams from various websites to video player of your choosing";
    homepage = "https://streamlink.github.io/";
    longDescription = ''
      Streamlink is a CLI utility that pipes videos from online
      streaming services to a variety of video players such as VLC, or
      alternatively, a browser.

      Streamlink is a fork of the livestreamer project.
    '';
    license = licenses.bsd2;
    mainProgram = "streamlink";
    maintainers = with maintainers; [ dezgeg zraexy DeeUnderscore ];
  };
}
