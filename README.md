# COSC2759 Assignment 2 - Semester 2, 2025

# Services


## Backend
This is the Backend Posts Service. It is responsible for talking to the Posts DB, and exposing an internal HTTP API for managing Posts.

### Environment Variables
| Environment Variable | Purpose                                                 |
|----------------------|---------------------------------------------------------|
| PORT                 | Which port will the service listen on for HTTP requests |
| DB_USER              | Username for connecting to the Backend DB               |
| DB_PASSWORD          | Password for connecting to the Backend DB               |
| DB_HOST              | Hostname/Network address for the Backend DB             |

### Image
The Backend service image is available at `rmitdominichynes/sdo-2025:backend`.

### Dependencies
The Backend service depends on a PostgreSQL database, with the required migrations. An image for this has been provided, available at `rmitdominichynes/sdo-2025:db`.

### Database Configuration
The PostgreSQL Databse container also requires some environment variables to be configured.

|  Environment Variable        |  Purpose                                                  |
|------------------------------|-----------------------------------------------------------|
|  POSTGRES_USER               | Username for the Backend Service to use to connect        |
|  POSTGRES_PASSWORD           | Password for the Backend Service to use to connect        |
|  POSTGRES_DB                 | "posts"                                                   |

## Frontend
This is the Frontend Posts Service. It is responsible for serving a UI to users over HTTP. This UI allows them to view and manage Posts.

### Environment Variables
| Environment Variable | Purpose                                                 |
|----------------------|---------------------------------------------------------|
| PORT                 | Which port will the service listen on for HTTP requests |
| BACKEND_URL          | Fully qualified URL for reaching the Backend Service    |

### Image
The Frontend service image is available at `rmitdominichynes/sdo-2025:frontend`.


# Running The Services Locally (In Docker)
1. Run `docker compose up -d` to start the two services, and a postgres database container.
2. View the Frontend Posts Service at `http://localhost:8081`, and the Backend Posts Service at `http://localhost:8080`.

# Deploying The Services

The services can be deployed to EC2. 

Each container needs: 
- The correct environment variables configured (refer to the above sections)
- Security Groups will need to be configured to allow traffic to reach the instances. 
    - They will also need to be configured to allow the instances to talk to each other, if the services are deployed on different instances.
    - The PostgreSQL database receives inbound traffic on port `5432`
    - The ports used by the Backend and Frontend services are configurable through the `PORT` environment variable. Otherwise, it will default to port `8081`.

# COSC2759 Assignment 2 - Semester 2, 2025 (s4125656-s4125640)
## Extended Project Documentation

---

## 1. Project Overview
Briefly explain the purpose of the project and what it achieves.  
- Purpose of the system (e.g., managing posts through CRUD operations)

We are *automating the deployment process* of our Posts app, including its infrastructure creation so that we can avoid human errors during the deployment process.

To achieve that we need to use the given AWS environment credentials and docker images so that when our GitHub Actions workflow runs *run the deployment script* we automatically deploy the infrastructure with the application running on it.

### Section A

In section A we are required to create a README.md in which it's this file. It'll be an extension of the default README.md given by the lecturers to explain what are the components we are adding to the GitHub repository.

Then we are required to make a bash script that fully automates the deployment process, in which it's the "deploy.sh" file on the root folder. This `deploy.sh` script automates the entire deployment process for the project from infrastructure setup to application configuration. It first uses Terraform (inside the `infra` directory) to provision the necessary AWS EC2 instances for the database, backend, and frontend. After the infrastructure is created, it retrieves each server’s public and private IP addresses using Terraform outputs. Then, it dynamically generates an Ansible inventory file containing these IPs and SSH connection details so Ansible knows where and how to connect. Once the instances have had time to boot (a 45-second pause), the script runs an Ansible playbook to configure and deploy the services on the servers. Finally, it prints a summary showing all server addresses and where to access the deployed application.

Lastly, we are required to make the connection between the backend service and database container that are deployed on at least one EC2 instance. The acceptance criteria is for the Backend Container successfully connect to the Database Container. This was done through combining Terraform and Ansible. Terraform is used to setup the EC2 instances, like their security groups in which allows the Backend Container to be able to connect to the Database container and for the Backkend Container to be reached by a user through HTTP. Ansible on the other hand is used for installing the frontend/backend/database modules through docker images inside the EC2 instance. To visualize it simply, Terraform is the architect and Ansible is the interior designer.

### Section B

### Section C

- Technologies used (Docker, PostgreSQL, Node.js/Express, React, etc.)  
- Description of the final architecture and its functionality  

---

## 2. System Architecture
Describe how the services interact with each other.  
- **Architecture Diagram:**  
  *(Insert or describe a diagram showing Frontend ↔ Backend ↔ Database)*  
- **Data Flow:** Explain how requests move through the system.  
- **Ports and Communication:** Note which ports each service uses and how they connect.  

---

## 3. Development Process
Outline the development steps and workflow.  
- Setting up local development environment  
- Key challenges faced during development  
- Solutions or debugging methods you applied  
- Tools and libraries used  

## 4. Implementation Details
Provide technical explanations of each component.  
### Backend
- Routes, endpoints, and database integration  
- How environment variables are used  
- Interaction with PostgreSQL  

### Frontend
- UI layout and key pages  
- API call structure and error handling  
- Environment variable setup for BACKEND_URL  

### Database
---

## 5. Docker & Deployment Setup
Explain how you containerized and deployed the project.  
- Overview of `docker-compose.yml`  
- Steps for running locally (`docker compose up -d`)  
- Steps for deploying to EC2  
- Common issues and how you resolved them (e.g., port conflicts, missing environment variables)  

---

## 6. Challenges & Lessons Learned
Reflect on what you encountered and learned.  
- Technical or deployment challenges  
- Key takeaways about Docker, EC2, or service communication  
- Ideas for future improvements  

---

## 7. References & Resources
List any documentation, tutorials, or guides you used.  
- Official Docker / PostgreSQL / AWS documentation  
- RMIT lab or assignment references  
- Online resources or guides  

---

## 8. Appendix
Include any supporting information.  
- Example `.env` file  
- Useful Docker or deployment commands  
- Configuration notes