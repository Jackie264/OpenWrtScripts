# CHANGELOG

## 2026-07-26

- **Printable Label** package that
  appears in Services -> Printable Label.
  Print the page to create a label that can be taped to the router
  with the model, OpenWrt version, and credentials
  to make it easy to connect to the router.
  
## 2024-10-02

- Add "-Z" to the netperf test at netperf.bufferbloat.net
- Update the
  [https://netperf.bufferbloat.net](https://netperf.bufferbloat.net) page
  to display each day's -Z passphrase

## 2024-09-24

- Add `config-spare-router.sh` script to reset an
  out-of-service OpenWrt router to current firmware
  and known configuration for easy re-use.

- Add `print-router-label.sh` script to print a label
  showing the configuration of a router.
  Used by `config-spare-router.sh`

## 2022-01-04

- Update `betterspeedtest.sh` to have better behavior
  if there are errors.
  
## [Many intervening releases]

## 2015-04-11

- Initial commit of this repo, cloning the earlier
  [CeroWrt scripts](https://github.com/richb-hanover/CeroWrtScripts) repo.
