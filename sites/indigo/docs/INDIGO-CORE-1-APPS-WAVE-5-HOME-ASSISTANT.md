# Wave 5 - Home Assistant Configuration

We assume you've followed the steps at:
* [`dal-indigo-core-1` Apps - Wave 5](INDIGO-CORE-1-APPS-WAVE-5.md) and have Home Assistant already running

At the moment we have Authentik Proxy Auth infront of HA until it [natively supports OIDC auth](https://github.com/orgs/home-assistant/discussions/48) this means the HA Mobile App remains broken due to not supporting this auth mechanism.

## Setup HACS

HACS will persist across Pod recreation events due to it being installed in the PV's directory `/config`.

```bash
# Debug into the HA pod
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n home-assistant exec -it ha-0 -- sh

$ wget -O - https://get.hacs.xyz | bash -
$ exit

# Restart the HA pod
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n home-assistant delete pod ha-0
```

Install HACS within HA:
* Reload your browser tab and log back into HA
* Add a new Integration and search for HACS
* Accept all the checkboxes and perform the github auth

You should now have a HACS menu item on the left!

## Other Integrations

A list of other integrations:
* [Airtouch 5](https://www.home-assistant.io/integrations/airtouch5/)
* [Emerald HWS (via HACS)](https://github.com/ross-w/emerald-hws-ha)
