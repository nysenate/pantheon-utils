<?php
/**
 * Project: NYSenate.gov website
 * Author: Ken Zalewski
 * Organization: New York State Senate
 * Date: 2016-07-19
 *
 * ReplicaInfo.php - A Terminus plugin that adds a new "replica-info"
 * subcommand to the "site" command of the Terminus CLI.
 *
 * See the README.md file for information on installing this plugin.
 *
 * DISCLAIMER!!!  Connecting to replica databases should only be done by those
 * who know what they are doing.  Writing to a replica database is highly
 * ill-advised, since the master database overwrites the replica and the risk
 * of data corruption is elevated.  In addition, Pantheon connection strings
 * change frequently due to endpoint migrations and such.  As a result, live
 * connections to the replica database will sometimes fail until the latest
 * connection string is retrieved.
 */

namespace Terminus\Commands;

use Terminus\Commands\TerminusCommand;
use Terminus\Models\Collections\Sites;

/**
 *
 * This is a subcommand of the 'site' command for retrieving information
 * about the MySQL replica connection.
 *
 * @command site
 */
class ReplicaInfoCommand extends TerminusCommand
{
  public function __construct(array $options = [])
  {
    $options['require_login'] = true;
    parent::__construct($options);
    $this->sites = new Sites();
  } // __construct()


  /**
   * Retrieve MySQL replica connection info for a specific environment
   *
   * [--site=<site>]
   * : name of the site
   *
   * [--env=<env>]
   * : environment for which to fetch connection info
   *
   * [--field=<field>]
   * : specific field to return
   *
   * @subcommand replica-info
   * @alias ri
   */
  public function outputReplicaInfo($args, $assoc_args)
  {
    $in = $this->input();
    $site = $this->sites->get($in->siteName(array('args' => $assoc_args)));
    $env_id = $in->env(array('args' => $assoc_args, 'site' => $site));
    $env = $site->environments->get($env_id);

    // We cannot use the getByType() method, because it explicitly ignores
    // any binding that has a "slave_of" attribute set.
    //$dbservers = (array)$env->bindings->getByType('dbserver');

    $all_bindings = $env->bindings->all();
    $dbservers = self::getDbServers($all_bindings, $env_id);

    if (count($dbservers) != 2) {
      $this->log()->error("There is no replication server for environment [$env_id]");
      return false;
    }

    // Confirm that the proper server is selected as the slave server by
    // making sure that the "slave_of" attribute is set and that it correctly
    // references the master server.
    if (empty($dbservers[0]->get('slave_of'))) {
      // Confirm that the second server is the slave.
      if ($dbservers[0]->get('id') !== $dbservers[1]->get('slave_of')) {
        $this->log()->error("Slave server is not referencing master properly");
        return false;
      }
      $dbserver = $dbservers[1];
    }
    else {
      // Confirm that the first server is the slave.
      if ($dbservers[1]->get('id') !== $dbservers[0]->get('slave_of')) {
        $this->log()->error("Slave server is not referencing master properly");
        return false;
      }
      $dbserver = $dbservers[0];
    }

    $mysql_params = self::getMysqlParams($dbserver);

    if (isset($assoc_args['field'])) {
      $field = $assoc_args['field'];
      $this->output()->outputValue($mysql_params[$field]);
    }
    else {
      $this->output()->outputRecord($mysql_params);
    }
    return true;
  } // outputReplicaInfo()



  /*
   * Given an array of bindings, this method returns only those bindings
   * that are of type 'dbserver'.  If the $env parameter is provided and
   * is not null, then only bindings in that environment will be returned.
   *
   * For reference, here are the various binding types:
   *   appserver, cacheserver, codeserver, dbserver,
   *   fileserver, indexserver, newrelic, pingdom
  */
  private function getDbServers($bindings, $env = null)
  {
    $db_bindings = [];
    foreach ($bindings as $binding) {
      if ($binding->get('type') === 'dbserver') {
        if (!$env || $env === $binding->get('environment')) {
          $db_bindings[] = $binding;
        }
      }
    }
    return $db_bindings;
  } // getDbServers()

      

  private function getMysqlParams($db_binding)
  {
    $env_id = $db_binding->get('environment');
    $site_id = $db_binding->get('site');

    $mysql_username = $db_binding->get('username');
    $mysql_password = $db_binding->get('password');
    $mysql_host = $db_binding->get('host');
    $mysql_hostname = sprintf('dbserver.%s.%s.drush.in', $env_id, $site_id);
    $mysql_port = $db_binding->get('port');
    $mysql_database = $db_binding->get('database');

    $mysql_url = sprintf(
      'mysql://%s:%s@%s:%s/%s',
      $mysql_username, $mysql_password,
      $mysql_host, $mysql_port, $mysql_database
    );

    $mysql_command = sprintf(
      'mysql -u %s -p%s -h %s -P %s %s',
      $mysql_username, $mysql_password,
      $mysql_host, $mysql_port, $mysql_database
    );

    return [
      'binding_id'     => $db_binding->get('id'),
      'mysql_username' => $mysql_username,
      'mysql_password' => $mysql_password,
      'mysql_host'     => $mysql_host,
      'mysql_hostname' => $mysql_hostname,
      'mysql_port'     => $mysql_port,
      'mysql_database' => $mysql_database,
      'mysql_url'      => $mysql_url,
      'mysql_command'  => $mysql_command,
      'mysql_slaveof'  => $db_binding->get('slave_of'),
    ];
  } // getMysqlParams()
}
