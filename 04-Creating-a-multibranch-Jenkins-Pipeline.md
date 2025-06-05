1. On the Jenkins dashboard, click "New Item"

2. Enter NAME as "PetClinic" and select "Multibranch Pipeline"

3. Configure the following:
    - Leave "Display Name" as empty

    - Branch Sources
        - GitHub
            - select the GitHub credentials (create a new one if one doesn't exist)
            - Repository HTTPS URL: https://github.com/vjkancherla/DevSecOps-ArgoCD

            - Behaviours
                - Discover branches
                    - All Branches
                - Filter by name (with wildcards)
                    - Include : feature/*

            - Build Configuration
                - by JenkinsFile 

