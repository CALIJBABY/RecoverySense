import 'package:flutter/material.dart';

class EmaScreen extends StatefulWidget {
  const EmaScreen({super.key});

  @override
  State<EmaScreen> createState() => _EmaScreenState();
}

class _EmaScreenState extends State<EmaScreen> {
  double _cravingScore = 3;
  final _noteController = TextEditingController();

  void _submit() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('EMA saved locally: craving score ${_cravingScore.round()}'),
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EMA Check-In'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Current Craving Level',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  const Text('How strong are your cravings right now?'),
                  const SizedBox(height: 20),
                  Center(
                    child: Text(
                      _cravingScore.round().toString(),
                      style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Slider(
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: _cravingScore.round().toString(),
                    value: _cravingScore,
                    onChanged: (value) => setState(() => _cravingScore = value),
                  ),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Low'),
                      Text('High'),
                    ],
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: _noteController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Optional note',
                      hintText: 'Context, location, stress, or activity...',
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _submit,
                    child: const Text('Submit EMA'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
