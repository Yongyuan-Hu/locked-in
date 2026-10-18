# Third-party notices

LockedIn includes the unmodified SelfControl 4.0.2 application as its blocking engine.

- Project: [SelfControl](https://selfcontrolapp.com/)
- Authors: Charlie Stigler, Steve Lambert, and the SelfControl contributors; individual copyright notices are preserved in the included source.
- License: GNU General Public License, version 3 or later. See `LICENSE` and `Vendor/SelfControl/COPYING`.
- Corresponding source: `Vendor/SelfControl/`, pinned to `4562c9716f83eb3cadbc8f6b3e9ecc3e2f672531` (the 4.0.2 / build 410 source commit).
- Upstream repository: https://github.com/SelfControlApp/selfcontrol
- Engine binary: https://downloads.selfcontrolapp.com/SelfControl-4.0.2.zip

The build preserves the engine application's signatures, resources, acknowledgments, and bundled dependency licenses. A copy of the engine source is included inside each built LockedIn app. The full source for the LockedIn frontend is distributed with this repository.

LockedIn is an independent project and is not an official SelfControl release. Its interface and integration code are new; the privileged firewall implementation remains the upstream engine.
