output "trigger_ids" {
  description = "Map of service name to Cloud Build trigger ID."
  value       = { for k, v in google_cloudbuild_trigger.service : k => v.trigger_id }
}
