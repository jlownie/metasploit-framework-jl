##
# This module requires Metasploit: https://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

class MetasploitModule < Msf::Auxiliary
  include Msf::Auxiliary::Report
  include Msf::Exploit::Remote::MYSQL
  include Msf::OptionalSession::MySQL

  def initialize(info = {})
    super(update_info(info,
        'Name'          => 'MySQL Enumeration Module',
        'Description'	=> %q{
          This module allows for simple enumeration of MySQL Database Server
          provided proper credentials to connect remotely.
        },
        'Author'        => [ 'Carlos Perez <carlos_perez[at]darkoperator.com>' ],
        'License'       => MSF_LICENSE,
        'SessionTypes'  => %w[MySQL],
        'References'    =>
        [
          [ 'URL', 'https://cisecurity.org/benchmarks.html' ]
        ]
      ))

  end

  def report_cred(opts)
    service_data = {
      address: opts[:ip],
      port: opts[:port],
      service_name: opts[:service_name],
      protocol: 'tcp',
      workspace_id: myworkspace_id
    }

    credential_data = {
      origin_type: :service,
      module_fullname: fullname,
      username: opts[:user],
      private_data: opts[:password],
      private_type: :nonreplayable_hash,
      jtr_format: 'mysql,mysql-sha1'
    }.merge(service_data)

    login_data = {
      core: create_credential(credential_data),
      status: Metasploit::Model::Login::Status::UNTRIED,
      proof: opts[:proof]
    }.merge(service_data)

    create_credential_login(login_data)
  end

  def run
    # If we have a session make use of it
    if session
      print_status("Using existing session #{session.sid}")
      self.mysql_conn = session.client
      self.sock = session.client.socket
    else
      # otherwise fallback to attempting to login
      return unless mysql_login_datastore
    end

    print_status("Running MySQL Enumerator...")
    print_status("Enumerating Parameters")
    #-------------------------------------------------------
    # getting all variables
    vparm = {}
    res = mysql_query("show variables") || []
    res.each do |row|
      # print_status(" | #{row.join(" | ")} |")
      vparm[row[0]] = row[1]
    end

    #-------------------------------------------------------
    # MySQL Version
    print_status("\tMySQL Version: #{vparm["version"]}")
    print_status("\tCompiled for the following OS: #{vparm["version_compile_os"]}")
    print_status("\tArchitecture: #{vparm["version_compile_machine"]}")
    print_status("\tServer Hostname: #{vparm["hostname"]}")
    print_status("\tData Directory: #{vparm["datadir"]}")

    if vparm["log"] == "OFF"
      print_status("\tLogging of queries and logins: OFF")
    else
      print_status("\tLogging of queries and logins: ON")
      print_status("\tLog Files Location: #{vparm["log_bin"]}")
    end

    print_status("\tOld Password Hashing Algorithm #{vparm["old_passwords"]}")
    print_status("\tLoading of local files: #{vparm["local_infile"]}")
    print_status("\tDeny logins with old Pre-4.1 Passwords: #{vparm["secure_auth"]}")
    print_status("\tSkipping of GRANT TABLE: #{vparm["skip_grant_tables"]}") if vparm["skip_grant_tables"]
    print_status("\tAllow Use of symlinks for Database Files: #{vparm["have_symlink"]}")
    print_status("\tAllow Table Merge: #{vparm["have_merge_engine"]}")
    print_status("\tRestrict DB Enumeration by Privilege: #{vparm["safe_show_database"]}") if vparm["safe_show_database"]

    if vparm["have_openssl"] == "YES"
      print_status("\tSSL Connections: Enabled")
      print_status("\tSSL CA Certificate: #{vparm["ssl_ca"]}")
      print_status("\tSSL Key: #{vparm["ssl_key"]}")
      print_status("\tSSL Certificate: #{vparm["ssl_cert"]}")
    else
      print_status("\tSSL Connection: #{vparm["have_openssl"]}")
    end

    #-------------------------------------------------------
    # Database selection
    query = "use mysql"
    mysql_query(query)

    # Account Enumeration
    # Enumerate all accounts with their password hashes
    print_status("Enumerating Accounts:")
    query = "select user, host, password from mysql.user"
    res = mysql_query(query)
    if res and res.size > 0
      print_status("\tList of Accounts with Password Hashes:")
      res.each do |row|
        print_good("\t\tUser: #{row[0]} Host: #{row[1]} Password Hash: #{row[2]}")
        report_cred(
          ip: mysql_conn.host,
          port: mysql_conn.port,
          user: row[0],
          password: row[2],
          service_name: 'mysql',
          proof: row.inspect
        )
      end
    end
    # Only list accounts that can log in with SSL if SSL is enabled
    if vparm["have_openssl"] == "YES"
      query = %Q|select user, host, ssl_type from mysql.user where
        (ssl_type = 'ANY') or
        (ssl_type = 'X509') or
        (ssl_type = 'SPECIFIED')|
      res = mysql_query(query)
      if res.size > 0
        print_status("\tThe following users can login using SSL:")
        res.each do |row|
          print_status("\t\tUser: #{row[0]} Host: #{row[1]} SSLType: #{row[2]}")
        end
      end
    end
    query = "select user, host from mysql.user where Grant_priv = 'Y'"
    res = mysql_query(query)
    if res and res.size > 0
      print_status("\tThe following users have GRANT Privilege:")
      res.each do |row|
        print_status("\t\tUser: #{row[0]} Host: #{row[1]}")
      end
    end

    query = "select user, host from mysql.user where Create_user_priv = 'Y'"
    res = mysql_query(query)
    if res and res.size > 0
      print_status("\tThe following users have CREATE USER Privilege:")
      res.each do |row|
        print_status("\t\tUser: #{row[0]} Host: #{row[1]}")
      end
    end
    query = "select user, host from mysql.user where Reload_priv = 'Y'"
    res = mysql_query(query)
    if res and res.size > 0
      print_status("\tThe following users have RELOAD Privilege:")
      res.each do |row|
        print_status("\t\tUser: #{row[0]} Host: #{row[1]}")
      end
    end
    query = "select user, host from mysql.user where Shutdown_priv = 'Y'"
    res = mysql_query(query)
    if res and res.size > 0
      print_status("\tThe following users have SHUTDOWN Privilege:")
      res.each do |row|
        print_status("\t\tUser: #{row[0]} Host: #{row[1]}")
      end
    end
    query = "select user, host from mysql.user where Super_priv = 'Y'"
    res = mysql_query(query)
    if res and res.size > 0
      print_status("\tThe following users have SUPER Privilege:")
      res.each do |row|
        print_status("\t\tUser: #{row[0]} Host: #{row[1]}")
      end
    end
    query = "select user, host from mysql.user where FILE_priv = 'Y'"
    res = mysql_query(query)
    if res and res.size > 0
      print_status("\tThe following users have FILE Privilege:")
      res.each do |row|
        print_status("\t\tUser: #{row[0]} Host: #{row[1]}")
      end
    end
    query = "select user, host from mysql.user where Process_priv = 'Y'"
    res = mysql_query(query)
    if res and res.size > 0
      print_status("\tThe following users have PROCESS Privilege:")
      res.each do |row|
        print_status("\t\tUser: #{row[0]} Host: #{row[1]}")
      end
    end
    queryinmysql = %Q|       select user, host
        from mysql.user where
        (Select_priv = 'Y') or
        (Insert_priv = 'Y') or
        (Update_priv = 'Y') or
        (Delete_priv = 'Y') or
        (Create_priv = 'Y') or
        (Drop_priv = 'Y')|
    res = mysql_query(queryinmysql)
    if res and res.size > 0
      print_status("\tThe following accounts have privileges to the mysql database:")
      res.each do |row|
        print_status("\t\tUser: #{row[0]} Host: #{row[1]}")
      end
    end


    # Anonymous Account Check
    queryanom = "select user, host from mysql.user where user = ''"
    res = mysql_query(queryanom)
    if res and res.size > 0
      print_status("\tAnonymous Accounts are Present:")
      res.each do |row|
        print_status("\t\tUser: #{row[0]} Host: #{row[1]}")
      end
    end

    # Blank Password Check
    queryblankpass = "select user, host, password from mysql.user where length(password) = 0 or password is null"
    res = mysql_query(queryblankpass)
    if res and res.size > 0
      print_status("\tThe following accounts have empty passwords:")
      res.each do |row|
        print_status("\t\tUser: #{row[0]} Host: #{row[1]}")
      end
    end

    # Wildcard host
    querywildcrd = 'select user, host from mysql.user where host = "%"'
    res = mysql_query(querywildcrd)
    if res and res.size > 0
      print_status("\tThe following accounts are not restricted by source:")
      res.each do |row|
        print_status("\t\tUser: #{row[0]} Host: #{row[1]}")
      end
    end

    mysql_logoff unless session
  end
end
