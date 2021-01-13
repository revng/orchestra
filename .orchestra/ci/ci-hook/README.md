## Howto deploy

* Copy the project directory somewhere (e.g. /opt/revng-ci)
* Create a virtualenv with the required dependencies
  ```
  sudo apt-get install python3-pip
  python3 -m venv venv
  source ./venv/bin/activate
  pip install -r requirements.txt
  deactivate
  ```
  **Warning**: it is important to create the virtualenv after copying 
  the project in its target directory. Virtualenvs are not relocatable.
* Create `config.json` file from config.example.json template
* Create `environment` file from `environment.example` template with secrets
  **Warning**: remember to `chown root:root` and `chmod 600`
* Create systemd service, replacing {{ application_root }} in `revng-ci.example.service`
* Install and enable systemd service
  ```
  sudo cp revng-ci.service /etc/systemd/system/revng-ci.service
  sudo cp revng-ci.socket /etc/systemd/system/revng-ci.socket
  sudo systemctl enable revng-ci.socket
  sudo systemctl start revng-ci.socket
  ```
