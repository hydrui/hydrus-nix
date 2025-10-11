# Hydownloader Nix Derivation
This is a mostly-straight-laced Nix derivation, but it does output some useful attributes for the modules.

# The importJob attribute
his contains the upstream Hydownloader default import job configuration, separated into sections so it is possible to customize each section individually or inject code at various points, while still keeping up with changes in the future.

The genImportJob.py script is designed to fail if a new (thusfar-unknown) section is added. The output importJob.json contains the source hash, and the derivation contains an assertion that it is up-to-date, which should prevent the file from lagging when the derivation is updated. (Maybe it should also contain the hash of genImportJob.py...)
