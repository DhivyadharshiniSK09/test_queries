
 
WITH base AS (

  SELECT

    id,

    name,

    age,

    salary,

    bonus_percent,

    is_active,

    join_date,

    login_time,

    created_ts,

    extra_info,
 
    id::NUMBER(38, 0)                         AS id_num,

    name::VARCHAR(200)                        AS name_vc,

    salary::FLOAT                             AS salary_f,

    login_time::TIME                          AS login_as_time,
 
    IFF(is_active, 'Y', 'N')                  AS active_flag,

    NVL(bonus_percent, 0.0)                   AS bonus_safe,

    ZEROIFNULL(bonus_percent)                 AS bonus_z,

    NULLIFZERO(bonus_percent)                 AS bonus_nz,

    DECODE(

      MOD(id, 3),

      0, 'bucket_a',

      1, 'bucket_b',

      'bucket_c'

    )                                         AS id_bucket,

    EQUAL_NULL(name, 'unknown')               AS name_is_unknown,

    NVL2(bonus_percent, salary * bonus_percent / 100, 0) AS bonus_amt,
 
    DATEADD('day', age, join_date)            AS synthetic_date,

    DATEADD('month', -1, $test_as_of)         AS month_start,

    DATEDIFF('day', join_date, $test_as_of)   AS tenure_days,

    DATEDIFF('year', join_date, created_ts::DATE) AS tenure_years_approx,

    TO_CHAR(created_ts, 'YYYY-MM-DD HH24:MI:SS') AS created_str,

    TO_DATE('20261006', 'YYYYMMDD')           AS literal_date,

    TO_TIME(login_time, 'HH24:MI:SS')         AS login_parsed,

    TO_TIMESTAMP_NTZ(login_time)              AS login_ts_ntz,

    DATE_TRUNC('month', join_date)            AS join_month,
 
    SPLIT_PART(name, ' ', 1)                  AS first_token,

    REGEXP_LIKE(name, '^[A-Za-z].*')          AS name_alpha,

    ILIKE(name, '%a%')                        AS name_has_a,

    STARTSWITH(name, 'A')                     AS name_starts_a,

    CONTAINS(name, 'test')                    AS name_has_test,

    TRIM(name)                                AS name_trim,

    LENGTH(name)                              AS name_len,
 
    ROUND(salary, 0)                          AS salary_round,

    CEIL(bonus_percent)                       AS bonus_ceil,

    FLOOR(bonus_percent)                      AS bonus_floor,

    MOD(age, 5)                               AS age_mod,

    BITAND(id, 7)                             AS id_bitand,

    HASH(id, name, salary)                    AS row_hash,
 
    extra_info:dept::STRING                   AS dept,

    extra_info:score::STRING                  AS score_str,

    extra_info:tags                           AS tags_variant,

    GET_PATH(extra_info, 'dept')::STRING      AS dept_path,

    OBJECT_CONSTRUCT(

      'id', id,

      'dept', extra_info:dept,

      'active', is_active

    )                                         AS profile_obj,

    TRY_TO_NUMBER(extra_info:score::STRING)   AS score_num,

    TRY_TO_DOUBLE(extra_info:score::STRING)   AS score_dbl,

    TRY_CAST(extra_info:score::STRING AS INT) AS score_int,
 
    TRY_TO_TIMESTAMP(login_time)              AS login_ts_try
 
  FROM PUBLIC.PUBLIC.DATATYPE_DEMO

  WHERE join_date <= $test_as_of

    AND NVL(is_active, FALSE) = TRUE

    AND salary BETWEEN 0::DECIMAL(10,2) AND 9999999.99::DECIMAL(10,2)

),
 
flat AS (

  SELECT

    b.*,

    f.value::STRING                           AS tag

  FROM base b,

       LATERAL FLATTEN(INPUT => b.tags_variant, OUTER => TRUE) f

),
 
ranked AS (

  SELECT

    id,

    name,

    age,

    salary,

    bonus_percent,

    is_active,

    join_date,

    created_ts,

    dept,

    tag,

    bonus_amt,

    tenure_days,

    ROW_NUMBER() OVER (

      PARTITION BY dept

      ORDER BY salary DESC, id

    )                                         AS rn_dept,

    RANK() OVER (ORDER BY salary DESC)        AS sal_rank,

    DENSE_RANK() OVER (ORDER BY age DESC)     AS age_dense_rank,

    LAG(salary, 1, 0) OVER (

      PARTITION BY dept ORDER BY join_date, id

    )                                         AS prev_salary,

    LEAD(salary, 1) OVER (

      PARTITION BY dept ORDER BY join_date, id

    )                                         AS next_salary,

    SUM(salary) OVER (

      PARTITION BY dept

      ORDER BY join_date

      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW

    )                                         AS running_sal,

    AVG(salary) OVER (PARTITION BY dept)      AS avg_sal_dept,

    MEDIAN(salary) OVER (PARTITION BY dept)   AS med_sal_dept,

    FIRST_VALUE(name) OVER (

      PARTITION BY dept ORDER BY join_date

    )                                         AS first_name_in_dept,

    COUNT(*) OVER (PARTITION BY dept)         AS cnt_dept

  FROM flat

  QUALIFY rn_dept <= 3

),
 
agg AS (

  SELECT

    dept,

    COUNT(*)                                  AS cnt,

    COUNT_IF(is_active)                       AS active_cnt,

    SUM(salary)                               AS total_salary,

    AVG(bonus_percent)                        AS avg_bonus_pct,

    MIN(join_date)                            AS min_join,

    MAX(created_ts)                           AS max_created,

    LISTAGG(DISTINCT name, ',')

      WITHIN GROUP (ORDER BY name)            AS names_csv,

    ARRAY_AGG(DISTINCT id)                    AS id_array,

    OBJECT_AGG(name, salary)                  AS name_salary_map,

    APPROX_COUNT_DISTINCT(id)                 AS approx_ids

  FROM ranked

  GROUP BY dept

  HAVING COUNT(*) > 0

)
 
SELECT

  r.id,

  r.name,

  r.dept,

  r.tag,

  r.salary,

  r.bonus_amt,

  r.tenure_days,

  r.rn_dept,

  r.running_sal,

  a.names_csv,

  a.total_salary,

  a.approx_ids

FROM ranked r

LEFT JOIN agg a

  ON r.dept <=> a.dept

ORDER BY r.dept NULLS LAST, r.salary DESC

LIMIT 100

SAMPLE (10 PERCENT);
 
SELECT *

FROM (

  SELECT dept, is_active, salary

  FROM PUBLIC.PUBLIC.DATATYPE_DEMO

  WHERE extra_info:dept IS NOT NULL

)

PIVOT (

  SUM(salary) FOR is_active IN (TRUE, FALSE)

) AS p (dept, sal_active, sal_inactive);
 
SELECT *

FROM (

  SELECT id, salary, bonus_percent

  FROM PUBLIC.PUBLIC.DATATYPE_DEMO

  WHERE id <= 5

)

UNPIVOT (

  amount FOR metric IN (salary, bonus_percent)

);
 
MERGE INTO PUBLIC.PUBLIC.DATATYPE_DEMO t

USING (

  SELECT

    id,

    ROUND(salary * (1 + NVL(bonus_percent, 0) / 100), 2) AS new_salary

  FROM PUBLIC.PUBLIC.DATATYPE_DEMO

  WHERE is_active = TRUE

) s

ON t.id = s.id

WHEN MATCHED AND s.new_salary <> t.salary THEN

  UPDATE SET t.salary = s.new_salary

WHEN NOT MATCHED THEN

  INSERT (id, name, age, salary, is_active, join_date, created_ts, extra_info)

  VALUES (s.id, 'placeholder', 0, s.new_salary, TRUE, CURRENT_DATE(), CURRENT_TIMESTAMP(), PARSE_JSON('{}'));
 
SELECT d.id, g.seq

FROM PUBLIC.PUBLIC.DATATYPE_DEMO d,

     TABLE(GENERATOR(ROWCOUNT => 3)) g(seq);
 
SELECT

  id,

  extra_info:parent_id::INT AS parent_id,

  name

FROM PUBLIC.PUBLIC.DATATYPE_DEMO

START WITH extra_info:parent_id IS NULL

CONNECT BY extra_info:parent_id::INT = PRIOR id;
 
