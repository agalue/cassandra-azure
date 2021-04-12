# Cassandra in Azure for OpenNMS

This is a Test Environment to evaluate the performance of a Production Ready [Cassandra](http://cassandra.apache.org) or [ScyllaDB](https://www.scylladb.com/) Cluster against latest [OpenNMS Horizon](https://www.opennms.com/) in [Azure](https://azure.microsoft.com/).

The objective is test the performance of a given Cassandra cluster, having a RAID0 made of 2 Premium SSDs (P30 ~ 1TB) per instance for `/var/lib/cassandra`. The number of instances depends on the size of `cassandra_ip_addresses` from [vars.tf](vars.tf).

The solution uses [Terraform](https://www.terraform.io) to build the infrastructure in `Azure`, and then uses [Ansible](https://www.ansible.com) to install and configure the applications and bootstrap the cluster properly.

# Insllation and Usage

* Install the Azure CLI.

* Make sure to have your Azure credentials updated.

   ```bash
   az login
   ```

* Install the Terraform binary from [terraform.io](https://www.terraform.io) (Version 0.12.x or newer required).

* Tweak the common settings on [vars.tf](vars.tf) if necessary, and make sure the size of the Cassandra cluster is consistent with the [Ansible Intentory](ansible/inventory.yaml).

* Execute the following commands from the repository's root directory (at the same level as the `.tf` files):

  ```shell
  terraform init
  terraform apply
  ```

  Terraform will install Ansible on the OpenNMS server and run the playbook. When it is done, you're ready to use the Metrics Stress command.

* Connect to the Karaf Shell through SSH:

  From the OpenNMS instance:

  ```shell
  ssh -o ServerAliveInterval=10 -p 8101 admin@localhost
  ```

  The OpenNMS Server allows SSH via its public IP.

* Execute the `opennms:stress-metrics` command on each OpenNMS server. The following is an example to generate fake samples to be injected into the cluster.

  For 20K:

  ```shell
  opennms:stress-metrics -r 60 -n 6000 -f 20 -g 5 -a 10 -s 1 -t 200 -i 300
  ```

  For 40K:

  ```shell
  opennms:stress-metrics -r 60 -n 12000 -f 20 -g 5 -a 10 -s 1 -t 200 -i 300
  ```

  For 100K:

  ```shell
  opennms:stress-metrics -r 60 -n 15000 -f 20 -g 5 -a 20 -s 1 -t 200 -i 300
  ```

  Using `Standard_DS4_v2` for OpenNMS and `Standard_DS3_v2` on a 3 nodes cluster using Cassandra 3.11.6 with OpenJDK 8, the solution was able to handle 20K samples per second, but not 40K. Interestingly, with Cassandra 4.0-alpha4 and OpenJDK 11, the solution was able to handle 40K samples per second without issues, meaning Cassandra 4 looks very promising in terms of performance improvements. Although, with ScyllaDB 4 I got even better performance compared with Cassandra 4 for the same load.

* Check the OpenNMS performance graphs to understand how it behaves. Additionally, you could check the Azure Console.

* Enjoy!

## Termination

To destroy all the resources:

```shell
terraform destroy
```
