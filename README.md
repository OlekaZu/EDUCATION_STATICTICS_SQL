# PROJECT_EDUCATION_STATICTICS
PostgreSQL procedures and functions for creating and analizing the data of education proccess. 

This project consists of different sql-scripts (**PostreSQL**), which allow to create database, fill it using import-procedure from .csv-file, export data to .csv-file, use various functions and procedures for analyzing.

### Structure of the project:
```
├── import_data
│   ├── Peers.csv
│   ├── Tasks.csv
|   ├── Checks.csv
|   ├── P2P.csv
|   ├── Verter.csv
|   ├── TransferredPoints.csv
|   ├── Friends.csv
|   ├── Recommendations.csv
|   ├── XP.csv
│   └── TimeTracking.csv
├── analytics.sql
├── before_start.sh
├── create_db.sql
├── export_import_procedures.sql
└── procedures_trigers_funstions.sql
```

Before sql-scripts lauching use _before_start.sh_ for finding the current local directory of the project and get access to the files from _import_data_ without errors.
