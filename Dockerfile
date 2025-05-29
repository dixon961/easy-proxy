# Use the original image as the base
FROM teddysun/xray

# Set a working directory (optional, but good practice)
WORKDIR /etc/xray

# Copy your local config directory into the image
# This includes your entrypoint.sh and any other Xray config files
COPY ./config/ /etc/xray/

# Ensure your entrypoint script is executable
# (You might also do this on your host system before building: chmod +x config/entrypoint.sh)
RUN chmod +x /etc/xray/entrypoint.sh

# The entrypoint is now part of the image, so it's defined here.
# The CMD from the base image will likely be used if your entrypoint.sh expects arguments
# or if it's a wrapper that eventually calls the original Xray binary.
ENTRYPOINT ["/etc/xray/entrypoint.sh"]

# Expose ports (for documentation and `docker run -P`)
# These are the same ports you expose in docker-compose.yml
EXPOSE 1080
EXPOSE 3128
