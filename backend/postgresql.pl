#
# The backend/ directory includes files that follows an interface that allows
# other database backends to be implemented without the need to alter the core.
#
# The file is named as $name$.pl where $name$ is the case-sensitive name for
# the database backend, this can be anything you like, but the name of the file
# you choose is very important to the name of the subroutines you have in this
# file.
#
# If you want to implement your own backend duplicate this file and make the
# changes where appropriate - but all subroutines whether they are used or not
# must stay in the file.
#

sub backend_postgresql_update_index {
	print $L{'downloadschema'};
	mbz_download_schema();
	print $L{'done'} . "\n";
	
	# we attempt to create language, load all the native functions and indexes. If the create
	# language or functions fail they will ultimatly be skipped.
	
	# for PostgreSQL we need to try CREATE LANGUAGE
	if($g_db_rdbms eq 'postgresql') {
		mbz_do_sql("CREATE LANGUAGE plpgsql");
	}
	
	open(SQL, "temp/CreateFunctions.sql");
	chomp(my @lines = <SQL>);
	my $full = "";
	foreach my $line (@lines) {
		# skip blank lines and single bracket lines
		next if($line eq "" || substr($line, 0, 2) eq "--" || substr($line, 0, 1) eq "\\");
		
		$full .= "$line\n";
		if(index($line, 'plpgsql') > 0) {
			#print "$full\n";
			mbz_do_sql($full);
			$full = "";
		}
	}
	close(SQL);
	
	open(SQL, "temp/CreateIndexes.sql");
	chomp(my @lines = <SQL>);
	foreach my $line (@lines) {
		# skip blank lines and single bracket lines
		next if($line eq "" || substr($line, 0, 2) eq "--" || substr($line, 0, 1) eq "\\" ||
		        substr($line, 0, 5) eq "BEGIN");
		
		print "$line\n";
		mbz_do_sql($line);
	}
	close(SQL);
	
	open(SQL, "temp/CreatePrimaryKeys.sql");
	chomp(my @lines = <SQL>);
	foreach my $line (@lines) {
		# skip blank lines and single bracket lines
		next if($line eq "" || substr($line, 0, 2) eq "--" || substr($line, 0, 1) eq "\\" ||
		        substr($line, 0, 5) eq "BEGIN");
		
		print "$line\n";
		mbz_do_sql($line);
	}
	close(SQL);
}


# backend_postgresql_update_schema()
# Attempt to update the scheme from the current version to a new version by creating a table with a
# dummy field, altering the tables by adding one field at a time them removing the dummy field. The
# idea is that given any schema and SQL file the new table fields will be added, the same fields
# will result in an error and the table will be left unchanged and fields and tables that have been
# removed from the new schema will not be removed from the current schema.
# This is a crude way of doing it. The field order in each table after it's altered will not be
# retained from the new schema however the field order should not have a big bearing on the usage
# of the database because name based and column ID in scripts that use the database will remain the
# same.
# It would be nice if this subroutine had a makeover so that it would check items before attempting
# to create (and replace) them. This is just so all the error messages and so nasty.
# @return Always 1.
sub backend_postgresql_update_schema {
	print $L{'downloadschema'};
	mbz_download_schema();
	print $L{'done'} . "\n";
	
	# this is where it has to translate PostgreSQL to MySQL
	# as well as making any modifications needed.
	open(SQL, "temp/CreateTables.sql");
	chomp(my @lines = <SQL>);
	my $table = "";
	foreach my $line (@lines) {
		# skip blank lines and single bracket lines
		next if($line eq "" || $line eq "(" || substr($line, 0, 1) eq "\\");
		
		my $stmt = "";
		if(substr($line, 0, 6) eq "CREATE") {
			$table = mbz_remove_quotes(substr($line, 13, length($line)));
			if(substr($table, length($table) - 1, 1) eq '(') {
				$table = substr($table, 0, length($table) - 1);
			}
			$table = mbz_trim($table);
			print $L{'table'} . " $table\n";
			$stmt = "CREATE TABLE \"$table\" (dummycolumn int) tablespace $g_tablespace";
		} elsif(substr($line, 0, 1) eq " " || substr($line, 0, 1) eq "\t") {
			my @parts = split(" ", $line);
			for($i = 0; $i < @parts; ++$i) {
				if(substr($parts[$i], 0, 2) eq "--") {
					@parts = @parts[0 .. ($i - 1)];
					last;
				}
				
				# because the original MusicBrainz database is PostgreSQL we only need to make
				# minimal changes to the SQL.
				
				if(substr($parts[$i], 0, 4) eq "CUBE" && !$g_contrib_cube) {
					$parts[$i] = "TEXT";
				}
			}
			if(substr(reverse($parts[@parts - 1]), 0, 1) eq ",") {
				$parts[@parts - 1] = substr($parts[@parts - 1], 0, length($parts[@parts - 1]) - 1);
			}
			next if($parts[0] eq "CHECK" || $parts[0] eq "CONSTRAINT" || $parts[0] eq "");
			$parts[0] = mbz_remove_quotes($parts[0]);
			$stmt = "ALTER TABLE \"$table\" ADD \"$parts[0]\" " .
				join(" ", @parts[1 .. @parts - 1]);
		} elsif(substr($line, 0, 2) eq ");") {
			$stmt = "ALTER TABLE \"$table\" DROP dummycolumn";
		}
		if($stmt ne "") {
			# if this statement fails its hopefully because the field exists
			$dbh->do($stmt) or print "";
		}
	}
	
	close(SQL);
	return 1;
}


# backend_postgresql_table_exists($tablename)
# Check if a table already exists.
# @return 1 if the table exists, otherwise 0.
sub backend_postgresql_table_exists {
	my $sth = $dbh->prepare("select count(1) as count from information_schema.tables ".
	                        "where table_name='$_[0]'");
	$sth->execute();
	my $result = $sth->fetchrow_hashref();
	return $result->{'count'};
}


# mbz_load_data()
# Load the data from the mbdump files into the tables.
# @return Always 1, but if something bad goes wrong like a file cannot be opened it will issue a
#         die().
sub backend_postgresql_load_data {
	my $temp_time = time();
	opendir(DIR, "mbdump") || die "Can't open ./mbdump: $!";
	@files = sort(grep { $_ ne '.' and $_ ne '..' } readdir(DIR));
	$count = @files;
	$i = 1;
	
	foreach my $file (@files) {
		my $t1 = time();
		$table = $file;
		next if($table eq "blank.file" || substr($table, 0, 1) eq '.');
		print "\n" . localtime() . ": Loading data into '$file' ($i of $count)...\n";
		
		# make sure the table exists
		next if(!mbz_table_exists($table));
  		
  		open(TABLEDUMP, "mbdump/$file") or warn("Error: cannot open file 'mbdump/$file'\n");
  		my $sth2 = $dbh->prepare("select count(1) from information_schema.columns ".
  		                         "where table_name='$table'");
		$sth2->execute();
		my $result2 = $sth2->fetchrow_hashref();
		
		$dbh->do("COPY $table FROM STDIN");
		while($readline = <TABLEDUMP>) {
			chomp($readline);
			
			# crop to make postgres happy
			my @cols = split('	', $readline);
			$dbh->pg_putcopydata(join('	', @cols[0 .. ($result2->{'count'} - 1)]) . "\n");
		}
		close(TABLEDUMP);
  		
  		$dbh->pg_putcopyend();
		my $t2 = time();
		print "Done (" . mbz_format_time($t2 - $t1) . ")\n";
		++$i;
	}
	
	closedir(DIR);
	my $t2 = time();
	print "\nComplete (" . mbz_format_time($t2 - $temp_time) . ")\n";
	return 1;
}


# be nice
return 1;