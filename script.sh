#!/bin/bash
# Update package list
echo "Updating package list..."
dnf update -y
# Install Apache web server (httpd)
echo "Installing Apache web server..."
dnf install -y httpd
# Install Python 3 and pip
echo "Installing Python 3 and pip..."
dnf install -y python3 python3-pip
# Install required Python packages
echo "Installing Python packages..."
pip3 install flask mysql-connector-python
# Start and enable httpd service
echo "Starting and enabling httpd service..."
systemctl start httpd
systemctl enable httpd
# Configure firewall to allow HTTP traffic
echo "Configuring firewall to allow HTTP traffic..."
dnf install -y firewalld
systemctl start firewalld
systemctl enable firewalld
firewall-cmd --permanent --add-service=http
firewall-cmd --reload
# Install MariaDB client (mysql)
echo "Installing MariaDB client..."
dnf install -y mariadb105
# Create a Flask application
echo "Creating Flask application..."
mkdir -p /opt/myapp
# Create a configuration file to store environment variables
cat > /opt/myapp/config.py << 'EOF'
# Database configuration
DB_HOST = "<your rds endpoint> "
DB_USER = "admin"
DB_PASSWORD = "< Your RDS password "
DB_NAME = "mysql"
EOF
# Create the Flask application
cat > /opt/myapp/app.py << 'EOF'
#!/usr/bin/env python3
from flask import Flask, render_template_string
import mysql.connector
import sys
# Import configuration
sys.path.append('/opt/myapp')
import config
app = Flask(__name__)
@app.route('/')
def index():
    return render_template_string('''
        <!DOCTYPE html>
        <html>
        <head>
            <title>EC2 Instance with MySQL Connector</title>
        </head>
        <body>
            <h1>Welcome to the EC2 Instance with MySQL Connector</h1>
            <p>This server has been configured with Flask and MySQL connector for Python.</p>
            <p><a href="/db-test">Test Database Connection</a></p>
        </body>
        </html>
    ''')
@app.route('/db-test')
def db_test():
    # Get database connection parameters from config file
    db_host = config.DB_HOST
    db_user = config.DB_USER
    db_password = config.DB_PASSWORD
    db_name = config.DB_NAME
    
    connection_info = {
        'host': db_host or 'Not configured',
        'user': db_user or 'Not configured',
        'database': db_name or 'Not configured',
        'password': '*' * 8 if db_password else 'Not configured'
    }
    
    error_message = None
    success_message = None
    version = None
    
    # Test the database connection
    try:
        if not all([db_host, db_user, db_password, db_name]):
            raise Exception("Missing configuration. Please update the config.py file with your database credentials.")
        
        # Attempt connection
        conn = mysql.connector.connect(
            host=db_host,
            user=db_user,
            password=db_password,
            database=db_name
        )
        
        # If connection successful
        cursor = conn.cursor()
        cursor.execute("SELECT VERSION()")
        version = cursor.fetchone()[0]
        cursor.close()
        conn.close()
        
        success_message = "Successfully connected to MySQL!"
        
    except Exception as e:
        # If connection fails
        error_message = f"Failed to connect to the database: {str(e)}"
    
    return render_template_string('''
        <!DOCTYPE html>
        <html>
        <head>
            <title>Database Connection Test</title>
            <style>
                body { font-family: Arial, sans-serif; margin: 20px; }
                .success { color: green; }
                .error { color: red; }
            </style>
        </head>
        <body>
            <h1>Database Connection Test</h1>
            <p>Attempting to connect to MySQL database:</p>
            <ul>
                <li>Host: {{ connection_info.host }}</li>
                <li>User: {{ connection_info.user }}</li>
                <li>Database: {{ connection_info.database }}</li>
                <li>Password: {{ connection_info.password }}</li>
            </ul>
            
            {% if success_message %}
                <p class="success">{{ success_message }}</p>
                <p>MySQL version: {{ version }}</p>
            {% endif %}
            
            {% if error_message %}
                <p class="error">{{ error_message }}</p>
                <p>Please update the database credentials in /opt/myapp/config.py file.</p>
            {% endif %}
            
            <p><a href="/">Back to home</a></p>
        </body>
        </html>
    ''', connection_info=connection_info, success_message=success_message, error_message=error_message, version=version)
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF
# Make the script executable
chmod +x /opt/myapp/app.py
# Create a simple startup script
cat > /opt/myapp/start.sh << 'EOF'
#!/bin/bash
cd /opt/myapp
python3 app.py > /var/log/flask-app.log 2>&1 &
echo $! > /var/run/flask-app.pid
EOF
chmod +x /opt/myapp/start.sh
# Create a systemd service file for the Flask app
echo "Creating systemd service for Flask app..."
cat > /etc/systemd/system/flask-app.service << 'EOF'
[Unit]
Description=Flask Application
After=network.target
[Service]
Type=forking
ExecStart=/opt/myapp/start.sh
PIDFile=/var/run/flask-app.pid
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
# Setup Apache as a reverse proxy to the Flask app
echo "Configuring Apache as a reverse proxy..."
cat > /etc/httpd/conf.d/flask-proxy.conf << 'EOF'
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    
    ProxyPreserveHost On
    ProxyPass / http://localhost:8080/
    ProxyPassReverse / http://localhost:8080/
    
    ErrorLog logs/flask-error_log
    CustomLog logs/flask-access_log combined
</VirtualHost>
EOF
# Install mod_proxy for Apache if not already installed
echo "Installing mod_proxy for Apache..."
dnf install -y mod_proxy_http
# Enable and start the Flask service
echo "Starting Flask application..."
systemctl daemon-reload
systemctl enable flask-app
systemctl start flask-app
# Restart Apache to apply changes
echo "Restarting Apache..."
systemctl restart httpd
echo "==================================================================="
echo "Setup complete!"
echo "To configure your database connection:"
echo "1. Edit /opt/myapp/config.py file with your database credentials"
echo "2. Restart the Flask service with: systemctl restart flask-app"
echo "==================================================================="

