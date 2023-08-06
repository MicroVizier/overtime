# Overtime

Record and track working time with overtime by MySQL. 
Ideal solution for SQL enthusiasts who need to easily report time spent on a project.

## Features

* Pure SQL code (MySQL compatible)
* Ready for GUI integration
* Supporting holidays (manual insertion)
* Total working time summary for the last or actual month
* Time category (job, holiday, other)
* Eight-hour workday target (built in)

## Instalation

Run whole SQL script (located in sql directory) from an arbitrary MySQL client. 
For example, bash line on Linux:
```
mysql < path/to/overtime/sql/overtime.sql
```

## Usages

### Run time tracking (if not running) and return working time per today.
```CALL overtime.run();```

### Stop time tracking and return working time per today.
```CALL overtime.run();```

### Stop my job and add extra 10 min.
```CALL overtime.pausePlus('0:10');```

### Today report.
```SELECT * FROM overtime.log where dt = CURRENT_DATE() order by `start`;```

### Last month track.
```SELECT * FROM overtime.report_last_month;```

### Summary for last month.
```SELECT * FROM overtime.sum_last_month;```

### Summary for this month up to yesterday.
```SELECT * FROM overtime.sum_this_month;```

### Example of manually entering 8 hours job that started at 7 o'clock.
```insert into overtime.log (dt, `start`, total) values ('2017-05-02', '07:00', '08:00');```
    
### Example of manually entering of one day leave (multi-day range cannot be entered).
```insert into overtime.log (`type`, dt, `start`, total) values ('holiday', '2017-06-14', '08:00', '08:00');```

### A visit to a doctor.
```insert into overtime.log (`type`, dt, `start`, `end`, note) values ('other', '2017-07-18', '13:38', '15:04', 'Doctor visit');```
    
### How to insert day off (national holiday).
```insert ignore freeday (dt) values ('2017-07-05'),('2017-07-06'),('2017-09-28');```
 
