# Docker optimization

## Goal

improve performance, reduce latency and increase speed

## Strategy

Instead of spinup docker when the user choose that the data is relevant for a single prompt.
use data base techniques like isolating the per prompt or per sesstion data using schema or equivalent techniques, if not available for the database use prefixs.
This way the docker can kept alive and can serve different sessions / requests in isolation. and the cleanup can clean the isolated data without having side effects.

## logic correctness

Lets the user decide about the isolation level (with recommendation of the skill, thet present as recommended, the recommended option should be checked in a way that the user can just press enter to accept it).
the different isolations are:

- user
- session
- request (per prompt)

in the future we will conside a shared endpoint for organization sharing
