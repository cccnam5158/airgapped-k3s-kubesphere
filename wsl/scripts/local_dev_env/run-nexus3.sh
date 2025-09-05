docker run -d --name nexus3 -p 18081:8081 -p 5000:5000 -e TZ=Asia/Seoul -v nexus-data:/nexus-data sonatype/nexus3:latest
