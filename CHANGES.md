## v1.0.0 (2019-02-02)

* split opam package into two separate ones: a core
  `arp` package and the `arp-mirage` implementation
  for MirageOS that has more dependencies.  This
  eliminates the use of depopts that was done previously
  to build the Mirage layer. (#7 @avsm)

* port build system to Dune (#7 @avsm). The `make coverage`
  and `make bench` targets will do the job of the previous
  topkg targets for those.

* minor fixes to ocamldoc comments to be compatible with
  odoc.

* use mirage-random and mirage-random-test instead of a
  nocrypto dependency in tests and bench (#7 @hannesm)

* import tests from mirage-tcpip (#8 @hannesm)

* depend on the ethernet opam package, no longer provided
  by tcpip >3.7.0 (#9 @hannesm)

## 0.2.3 (2019-01-04)

* port to ipaddr 3.0.0

## 0.2.2 (2018-08-25)

* remove Arp_wire module, now integrated into Arp_packet
* remove usage of ppx_cstruct

## 0.2.1 (2018-05-06)

* Avoid an initial gratitious ARP with Ipaddr.V4.any

## 0.2.0 (2017-01-17)

* MirageOS3 support
* Don't ship with -warn-error +A, use it only in `./build`
* Fix testsuite compilation on OCaml 4.02
* Renamed `Marp` to `Arpv4` (same as MirageOS ARP handler in tcpip)

## 0.1.1 (2016-07-13)

* Minor nits for topkg

## 0.1.0 (2016-07-12)

* Initial release
