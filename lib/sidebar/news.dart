import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class NewsPage extends StatefulWidget {
  const NewsPage({super.key});

  @override
  _NewsPageState createState() => _NewsPageState();
}

class _NewsPageState extends State<NewsPage> {
  final List<Map<String, dynamic>> newsList = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchNews();
  }

  Future<void> fetchNews() async {
    final keywords = [
      'kidnapped',
      'harassed',
      'raped',
      'abused',
      'domestic violence',
      'trafficked',
      'assaulted',
      'violence against women'
    ];
    const apiUrl = 'https://newsapi.org/v2/everything';
    const apiKey = '3adddf09e8fc4c93acfae223e9540409'; // Your API key

    try {
      for (String keyword in keywords) {
        final response = await http.get(
          Uri.parse('$apiUrl?q=$keyword&apiKey=$apiKey&language=en&pageSize=10'),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final articles = data['articles'] as List;

          setState(() {
            for (var article in articles) {
              final newsItem = {
                'title': article['title'],
                'description': article['description'],
                'url': article['url'],
              };
              if (!newsList.contains(newsItem)) {
                newsList.add(newsItem); // Avoid duplicate articles
              }
            }
          });
        } else {
          print('Error: Failed to fetch news (Status: ${response.statusCode})');
        }
      }
    } catch (error) {
      print('Error fetching news: $error');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'News',
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
        backgroundColor: Colors.purple, // Purple AppBar
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : newsList.isEmpty
              ? const Center(child: Text('No news found'))
              : ListView.builder(
                  itemCount: newsList.length,
                  itemBuilder: (context, index) {
                    final news = newsList[index];
                    return Card(
                      margin: const EdgeInsets.all(8.0),
                      child: ListTile(
                        title: Text(news['title'] ?? 'No Title'),
                        subtitle: Text(news['description'] ?? 'No Description'),
                        onTap: () {
                          if (news['url'] != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Open: ${news['url']}')),
                            );
                          }
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
