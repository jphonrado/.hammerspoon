# New run records

The controller creates separate test/pilot/main participant and run directories here.
No records from the original ZIP are reused. Keep names and consent files separate.
`main_data.csv` contains UNVERIFIED controller estimates. Final performance data
come from OBS coding; `tools/encode_session.py` exports `analysis_trials.csv`
and `condition_summary.csv` without substituting those estimates.
Retain the raw data and the generated video-coding worksheet.
NASA-TLX remains in the separate Google Forms survey. The performance exporter
provides participant/condition join keys. See ../docs/ENCODING.md.
See ../DATA_DICTIONARY.md and ../README.md for session guards and recovery rules.
