# Patch licensing and scope

`0001-crfpmoc-negotiate-fp-info-version.patch` modifies libfprint source and
is distributed under the same LGPL-2.1-or-later terms stated in the modified
upstream files. It applies only to commit
`4df05918f4670f5eed684c1771d2183f2e2df279`; `install.sh` verifies both the
commit and patch checksum before applying it.

The patch negotiates `EC_CMD_FP_INFO`, parses legacy v1 and current v2/v3
metadata layouts, and leaves the existing v1 ioctl replay fixture usable.
