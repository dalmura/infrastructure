# Indigo Observability

After [INDIGO-CORE-1-APPS-WAVE-4.md](INDIGO-CORE-1-APPS-WAVE-4.md) has been deployed and configured, you have a basic setup that includes:
* Node Exporter
* [VictoriaLogs (VL) - Single](https://vls.indigo.dalmura.cloud/)
* VictoriaLogs (VL) - Collector
* [VictoriaMetrics (VM) - Single](https://vms.indigo.dalmura.cloud/)
* [VictoriaMetrics (VM) - Alert](https://vma.indigo.dalmura.cloud/)
* [Grafana](https://grafana.indigo.dalmura.cloud/)

Everything below uses the short terminology VL and VM.


## Configuration

* Both VL and VM's 'Single' apps are databases that store logs and metrics respectively
  * Single in this case meaning non-clustered
* They both have PVC's that are *not* backed up to S3, but replicated locally
  * We're ok with data loss if it happens
* VL Single has 7 days of log retention
* VM Single has 6 months of metric retention


## Log Collection

VL Collector automatically deploys itself across the cluster and sync *all* container logs into the VL Single instance.

Nothing else at the moment is writing *into* VL Single.


## Metric Collection

VM Single itself is configured with metric scraping jobs, these are (currently):
* VL Single metrics
* Longhorn metrics
* Node Exporter metrics

See (VM Single's Helm values.yaml file for more info)[../clusters/dal-indigo-core-1/wave-4/values/victoria-metrics-single/values.yaml].


## Alerting

VM Alert manages the alerting by:
* Connects to VM Single as the datasource
* Configured with a list of alert definitions:
  * Metric query that evaluates to true (raise alert/keep alert open) or false (do nothing/resolve alert)
  * Alert destination
    * Currently just Slack is configured
    * PagerDuty is possible as well


## Visualisation

Grafana manages the BI dashboarding of all the logs and metrics.

This currently is configured with the following Datasources:
* Prometheus (VictoriaMetrics fake interop)
  * Via `http://victoria-metrics-single-vms-server.victoria-metrics.svc.cluster.local:8428/`
* VictoriaLogs
  * Via `http://victoria-logs-single-vls-server.victoria-logs.svc.cluster.local:9428/`
* VictoriaMetrics
  * Via `http://victoria-metrics-single-vms-server.victoria-metrics.svc.cluster.local:8428/`

And the following public dashboards:
* [Longhorn Observability](https://grafana.com/grafana/dashboards/22705-longhorn-dashboard/)
* [Node Exporter Full](https://grafana.com/grafana/dashboards/1860-node-exporter-full/)
