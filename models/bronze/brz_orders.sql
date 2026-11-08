-- Bronze: a 1:1, untransformed view over the landed data.
-- Its only job is to give every downstream model a single, version-controlled entry point.
select * from {{ source('raw', 'orders') }}
