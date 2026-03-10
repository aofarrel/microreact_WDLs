version 1.0

workflow Microreact_Unshare_Projects_With_Team {
	input {
		File token
		String team_uri
		File project_uris
		Int max_python_retries     = 1
		Int max_wdl_retries        = 0
	}

	call mr_unshare_MULTIPLE_with_team {
		input:
			token = token,
			team_uri = team_uri,
			project_uris = project_uris,
			max_python_retries = max_python_retries,
			max_wdl_retries = max_wdl_retries
	}

}

task mr_unshare_MULTIPLE_with_team {
	input {
		File token
		String team_uri
		File project_uris
		Int max_python_retries
		Int max_wdl_retries
	}
	
	command <<<
		set -eu pipefail
		set +x
		# unbuffered, so we have some idea of its progress
		python3 -u << CODE
		import requests
		import time
		import json

		with open("~{token}", 'r', encoding="utf-8") as file:
			TOKEN_STR = file.readline().strip()

		with open("~{project_uris}", 'r', encoding="utf-8") as file:
			PROJECT_URIS = [uri.strip("\n") for uri in file.readlines()]

		def wait(retries):
			if ~{max_python_retries} - retries == 1:
				print("WAITING ONE MINUTE, THEN RETRYING...")
				time.sleep(60)
			elif ~{max_python_retries} - retries <= 0:
				return
			else:
				print("WAITING TWO SECONDS, THEN RETRYING...")
				time.sleep(2)
		
		def rm_mr_project_from_team(token, this_payload, retries=-1):
			if retries < ~{max_python_retries}:
				try:
					response = requests.post("https://microreact.org/api/shares/remove-team",
						headers={"Access-Token": token, "Content-Type": "application/json; charset=UTF-8"},
						timeout=20,
						data=this_payload)
					if response.status_code == 200:
						print(f"[INFO] Successfully unshared {json.loads(this_payload)['project']}")
						return
					print(f"Failed to unshare project {json.loads(this_payload)['project']} from ~{team_uri} [code {response.status_code}]: {response.text}")
					retries =+ 1
					wait(retries)
					rm_mr_project_from_team(token, this_payload, retries)
				except Exception as e: # ignore: broad-exception-caught
					print(f"Caught exception trying to unshare project {json.loads(this_payload)['project']} from team ~{team_uri}: {e}")
					retries =+ 1
					wait(retries)
					rm_mr_project_from_team(token, this_payload, retries)
			else:
				print(f"Failed to unshare project {json.loads(this_payload)['project']} from team ~{team_uri} after ~{max_python_retries} retries. Something's broken.")
				exit(1)

		batch_count = 0
		call_count = 0

		for i, project_uri in enumerate(PROJECT_URIS):
			payload_dict = {
				"team": "~{team_uri}",
				"project": project_uri
			}
			payload = json.dumps(payload_dict)

			rm_mr_project_from_team(TOKEN_STR, payload)
			call_count += 1
			time.sleep(1)

			# After every 20 calls, wait 20 seconds
			if call_count % 20 == 0:
				batch_count += 1
				print("[INFO] Completed batch of 20. Waiting 20 seconds...")
				time.sleep(20)

				# After every 20 batches (400 calls), wait 5 minutes
				if batch_count % 20 == 0:
					print("[INFO] Completed 20 batches (400 calls). Waiting 5 minutes...")
					time.sleep(300)

		CODE

	>>>

	runtime {
		cpu: 2
		disks: "local-disk 10 HDD"
		docker: "ashedpotatoes/dropkick:0.0.2"
		memory: "8 GB"
		maxRetries: max_wdl_retries
	}
}