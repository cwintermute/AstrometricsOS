mkdir -p ~/indi-web
cd ~/indi-web
python3 -m venv venv
source venv/bin/activate
pip3 install indiweb importlib-metadata
deactivate