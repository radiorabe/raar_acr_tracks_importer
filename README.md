# raar_acr_tracks_importer

Fetch tracks recognized by [ACR Cloud](https://www.acrcloud.com/) and import them into [raar](https://github.com/radiorabe/raar).

See configuration in `config/settings.example.yml`. Copy this file to `config/settings.yml`, complete it and run `raar_acr_tracks_importer.rb`.


## Deployment

## Initial

* Install dependencies: `yum install gcc gcc-c++ glibc-headers rh-ruby22-ruby-devel rh-ruby22-rubygem-bundler libxml2-devel libxslt-devel`
* Create a user on the server:
  * `useradd --home-dir /opt/raar-acr-tracks-importer --create-home --user-group raar-acr-tracks-importer`
  * `usermod -a -G raar-acr-tracks-importer <your-ssh-user>`
  * Add your SSH public key to `/opt/raar-acr-tracks-importer/.ssh/authorized_keys`.
* Perform the every time steps.
* Copy `settings.example.yml` to `settings.yml` and add the missing credentials.
* Copy both systemd files from `config` to `/etc/systemd/system/`.
* Enable and start the systemd timer: `systemctl enable --now raar-acr-tracks-importer.timer`

## Every time

* Prepare the dependencies on your local machine: `bundle package --all-platforms`
* SCP or Rsync all files: `rsync -avz --exclude .git --exclude .bundle --exclude config/settings.yml . raar-acr-tracks-importer@server:/opt/raar-acr-tracks-importer/`.
* Install the dependencies on the server (as `raar-acr-tracks-importer` in `/opt/raar-acr-tracks-importer`):
  `source /opt/rh/rh-ruby22/enable && bundle install --deployment --local`


## License

raar_acr_tracks_importer is released under the terms of the GNU Affero General Public License.
Copyright 2019 Radio RaBe.
See `LICENSE` for further information.
