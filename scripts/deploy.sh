# https://github.com/tsuzuki-takaaki/isucon/blob/main/setup/restart.sh
# TODO: migrationの追加 like this ↓↓↓↓

# Recreate database
# sudo mysql -e "DROP DATABASE isupipe"
# sudo mysql -e "CREATE DATABASE isupipe"
# Migrate with new schema
# sudo mysql -D isupipe < /home/isucon/webapp/sql/initdb.d/10_schema.sql
# Seed
# ~/webapp/sql/init.sh
