# raar_acr_tracks_importer

Fetch tracks recognized by [ACR Cloud](https://www.acrcloud.com/) and import them into [raar](https://github.com/radiorabe/raar).

See configuration in `config/settings.example.yml`. Copy this file to `config/settings.yml`, complete it and run `bin/raar_acr_tracks_importer.rb`.


## Deployment

## Initial

* Install dependencies: `yum install gcc gcc-c++ glibc-headers rh-ruby30-ruby-devel rh-ruby30-rubygem-bundler libxml2-devel libxslt-devel`
* Create a user on the server:
  * `useradd --home-dir /opt/raar-scripts --create-home --user-group raar-scripts`
  * `usermod -a -G raar-scripts <your-ssh-user>`
  * Add your SSH public key to `/opt/raar-scripts/.ssh/authorized_keys`.
* Create the script home directory: `mkdir -p /opt/raar-acr-tracks-importer/`.
* Configure bundler: `cd /opt/raar-acr-tracks-importer && bundle config set --local deployment 'true'`
* Perform the every time steps.
* Copy `settings.example.yml` to `settings.yml` and add the missing credentials.
* Copy both systemd files from `config` to `/etc/systemd/system/`.
* Enable and start the systemd timer: `systemctl enable --now raar-acr-tracks-importer.timer`

## Every time

* Prepare the dependencies on your local machine: `bundle package --all-platforms`
* SCP or Rsync all files: `rsync -avz --exclude .git --exclude .bundle --exclude config/settings.yml . raar-scripts@server:/opt/raar-acr-tracks-importer/`.
* Install the dependencies on the server (as `raar-scripts` in `/opt/raar-acr-tracks-importer`):
  `source /opt/rh/rh-ruby30/enable && bundle install --local`


## License

raar_acr_tracks_importer is released under the terms of the GNU Affero General Public License.
Copyright 2019-2022 Radio RaBe.
See `LICENSE` for further information.
