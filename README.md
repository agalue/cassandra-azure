# Cassandra in Azure for OpenNMS

This is a Test Environment to evaluate the performance of a Production Ready [Cassandra](http://cassandra.apache.org) Cluster against latest [OpenNMS Horizon](https://www.opennms.com/).

# Insllation and Usage

* Install the Azure CLI.

* Make sure to have your Azure credentials updated.

   ```bash
   az login
   ```

* Install the Terraform binary from [terraform.io](https://www.terraform.io)

> *NOTE*: The templates requires Terraform version 0.12.x.

* Tweak the common settings on [vars.tf](vars.tf).

* Execute the following commands from the repository's root directory (at the same level as the `.tf` files):

  ```shell
  terraform init
  terraform plan
  terraform apply -auto-approve
  ```

* Wait for the Cassandra cluster and OpenNMS to be ready, prior execute the `metrics:stress` command.

  Use the `nodetool status` command to verify that all the required instances have joined the cluster.

  OpenNMS will wait only for the seed node to create the Newts keyspace and once the UI is available, it creates a requisition with 2 nodes: the OpenNMS server itself and the Cassandra Seed Node, to collect statistics through JMX and SNMP every 30 seconds. This will help with the analysis.

* Connect to the Karaf Shell through SSH:

  From the OpenNMS instance:

  ```shell
  ssh -o ServerAliveInterval=10 -p 8101 admin@localhost
  ```

  Use the bastion for this purpose or SSH via the Public IP of the OpenNMS server.

* Execute the `metrics:stress` command on each OpenNMS server. The following is an example to generate fake samples to be injected into the cluster:

  ```shell
  metrics:stress -r 60 -n 15000 -f 20 -g 5 -a 10 -s 1 -t 200 -i 300
  ```

  For 100K:

  ```shell
  metrics:stress -r 60 -n 15000 -f 20 -g 5 -a 20 -s 1 -t 200 -i 300
  ```

  On a side note, injecting 50K samples per second means that OpenNMS is collecting data from 15 million unique samples every 5 minutes. For 100K, 30 million.

* Check the OpenNMS performance graphs to understand how it behaves. Additionally, you could check the Azure Console.

* Enjoy!

## Termination

To destroy all the resources:

```shell
terraform destroy
```
