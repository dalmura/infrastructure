# Wave 5 - Home Assistant Configuration

We assume you've followed the steps at:
* [`dal-indigo-core-1` Apps - Wave 5](INDIGO-CORE-1-APPS-WAVE-5.md) and have Home Assistant already running

Previously, Authentik Proxy Auth was enabled in front of HA, which broke the HA Mobile App login process. We have removed Authentik Proxy Auth from the main HA ingress (`ha.indigo.dalmura.cloud`) so users connect directly to Home Assistant and authenticate via its built-in authentication layer. Note that the code-server helper (`ha-code.indigo.dalmura.cloud`) remains Authentik-protected for security.

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
